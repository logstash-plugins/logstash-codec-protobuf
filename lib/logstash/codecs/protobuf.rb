# encoding: utf-8
require 'logstash/codecs/base'
require 'logstash/util/charset'
require 'google/protobuf' # for protobuf3
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers, for protobuf2

# This codec converts protobuf encoded messages into logstash events and vice versa. 
#
# Requires the protobuf definitions as ruby files. You can create those using the [ruby-protoc compiler](https://github.com/codekitchen/ruby-protocol-buffers).
# 
# The following shows a usage example for decoding protobuf 2 encoded events from a kafka stream:
# [source,ruby]
# kafka 
# {
#  zk_connect => "127.0.0.1"
#  topic_id => "your_topic_goes_here"
#  key_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
#  value_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
#  codec => protobuf 
#  {
#    class_name => "Animal::Unicorn"
#    include_path => ['/path/to/protobuf/definitions/UnicornProtobuf.pb.rb']
#  }
# }
#
# Same example for protobuf 3:
# [source,ruby]
# kafka 
# {
#  zk_connect => "127.0.0.1"
#  topic_id => "your_topic_goes_here"
#  key_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
#  value_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
#  codec => protobuf 
#  {
#    class_name => "Animal.Unicorn"
#    include_path => ['/path/to/protobuf/definitions/UnicornProtobuf_pb.rb']
#    protobuf_version => 3
#  }
# }
#
# Specifically for the kafka input: please set the deserializer classes as shown above.

class LogStash::Codecs::Protobuf < LogStash::Codecs::Base
  config_name 'protobuf'

  # Name of the class to decode.
  # If your protobuf 2 definition contains modules, prepend them to the class name with double colons like so:
  # [source,ruby]
  # class_name => "Animal::Horse::Unicorn"
  # 
  # This corresponds to a protobuf definition starting as follows:
  # [source,ruby]
  # module Animal
  #   module Horse
  #     class Unicorn
  #       # here are your field definitions.
  #
  # For protobuf 3 separate the modules with single dots.
  # [source,ruby]
  # class_name => "Animal.Horse.Unicorn"
  # Check the bottom of the generated protobuf ruby file. It contains lines like this:
  # [source,ruby]
  # Animals.Unicorn = Google::Protobuf::DescriptorPool.generated_pool.lookup("Animals.Unicorn").msgclass
  # Use the parameter for the lookup call as the class_name for the codec config.
  # 
  # If your class references other definitions: you only have to add the main class here.
   config :class_name, :validate => :string, :required => true

  # List of absolute pathes to files with protobuf definitions. 
  # When using more than one file, make sure to arrange the files in reverse order of dependency so that each class is loaded before it is 
  # refered to by another.
  # 
  # Example: a class _Unicorn_ referencing another protobuf class _Wings_
  # [source,ruby]
  # module Animal
  #   module Horse
  #     class Unicorn
  #       set_fully_qualified_name "Animal.Horse.Unicorn"
  #       optional ::Animal::Bodypart::Wings, :wings, 1
  #       optional :string, :name, 2
  #       # here be more field definitions
  #
  # would be configured as
  # [source,ruby]
  # include_path => ['/path/to/protobuf/definitions/Wings.pb.rb','/path/to/protobuf/definitions/Unicorn.pb.rb']
  #
  # When using the codec in an output plugin: 
  # * make sure to include all the desired fields in the protobuf definition, including timestamp. 
  #   Remove fields that are not part of the protobuf definition from the event by using the mutate filter.
  # * the @ symbol is currently not supported in field names when loading the protobuf definitions for encoding. Make sure to call the timestamp field "timestamp" 
  #   instead of "@timestamp" in the protobuf file. Logstash event fields will be stripped of the leading @ before conversion.
  #  
  config :include_path, :validate => :array, :required => true

  # Protocol buffer version switch. Defaults to version 2. Please note that the behaviour for enums varies between the versions. 
  # For protobuf 2 you will get integer representations for enums, for protobuf 3 you'll get string representations due to a different converter library.
  # Recommendation: use the translate plugin to restore previous behaviour when upgrading.
  config :protobuf_version, :validate => [2,3], :default => 2, :required => true

  # To tolerate faulty messages that cannot be decoded, set this to false. Otherwise the pipeline will stop upon encountering a non decipherable message.
  config :stop_on_error, :validate => :boolean, :default => false, :required => false

  def register
    @metainfo_messageclasses = {}
    @metainfo_enumclasses = {}
    @metainfo_pb2_enumlist = []
    include_path.each { |path| load_protobuf_definition(path) }
    if @protobuf_version == 3   
      @pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup(class_name).msgclass
    else
      @pb_builder = pb2_create_instance(class_name)
    end
  end


  def decode(data)
    if @protobuf_version == 3
      decoded = @pb_builder.decode(data.to_s)
      h = pb3_deep_to_hash(decoded)
    else
      decoded = @pb_builder.parse(data.to_s)
      h = decoded.to_hash        
    end
    yield LogStash::Event.new(h) if block_given?
  rescue => e
    @logger.warn("Couldn't decode protobuf: #{e.inspect}.")
    if stop_on_error
      raise e
    end
  end # def decode


  def encode(event)
    if @protobuf_version == 3
      protobytes = pb3_encode_wrapper(event)
    else
      protobytes = pb2_encode_wrapper(event)     
    end
     @on_event.call(event, protobytes)
  end # def encode


  private
  def pb3_deep_to_hash(input)
    case input
    when Google::Protobuf::MessageExts # it's a protobuf class
      result = Hash.new
      input.to_hash.each {|key, value|
        result[key] = pb3_deep_to_hash(value) # the key is required for the class lookup of enums.
      }      
    when ::Array
      result = []
      input.each {|value|
          result << pb3_deep_to_hash(value)
      }
    when ::Hash
      result = {}
      input.each {|key, value|
          result[key] = pb3_deep_to_hash(value)
      }
    when Symbol # is an Enum
      result = input.to_s.sub(':','')
    else
      result = input
    end
    result
  end

  def pb3_encode_wrapper(event)
    data = pb3_encode(event.to_hash, @class_name)
    pb_obj = @pb_builder.new(data)
    @pb_builder.encode(pb_obj)
  rescue ArgumentError => e
    k = event.to_hash.keys.join(", ")
    @logger.debug("Encoding error 2. Probably mismatching protobuf definition. Required fields in the protobuf definition are: #{k} and the timestamp field name must not include an @.")
    raise e
  rescue => e
    @logger.debug("Couldn't generate protobuf: #{e.inspect}")
    raise e
  end


  def pb3_encode(datahash, class_name)
    if datahash.is_a?(::Hash)
      
    

      # Preparation: the data cannot be encoded until certain criteria are met:
      # 1) remove @ signs from keys.
      # 2) convert timestamps and other objects to strings
      datahash = datahash.inject({}){|x,(k,v)| x[k.gsub(/@/,'').to_sym] = (should_convert_to_string?(v) ? v.to_s : v); x}
      
      # Check if any of the fields in this hash are protobuf classes and if so, create a builder for them.
      meta = @metainfo_messageclasses[class_name]
      if meta
        meta.map do | (field_name,class_name) |
          key = field_name.to_sym
          if datahash.include?(key)
            original_value = datahash[key] 
            datahash[key] = 
              if original_value.is_a?(::Array)
                # make this field an array/list of protobuf objects
                # value is a list of hashed complex objects, each of which needs to be protobuffed and
                # put back into the list.
                original_value.map { |x| pb3_encode(x, class_name) } 
                original_value
              else 
                r = pb3_encode(original_value, class_name)
                builder = Google::Protobuf::DescriptorPool.generated_pool.lookup(class_name).msgclass
                builder.new(r)              
              end # if is array
          end # if datahash_include
        end # do
      end # if meta

      # Check if any of the fields in this hash are enum classes and if so, create a builder for them.
      meta = @metainfo_enumclasses[class_name]
      if meta
        meta.map do | (field_name,class_name) |
          key = field_name.to_sym
          if datahash.include?(key)
            original_value = datahash[key]
            datahash[key] = case original_value
            when ::Array
              original_value.map { |x| pb3_encode(x, class_name) } 
              original_value
            when Fixnum
              original_value # integers will be automatically converted into enum
            # else
              # feature request: support for providing integers as strings or symbols.
              # not fully tested yet:
              # begin
              #   enum_lookup_name = "#{class_name}::#{original_value}"
              #   enum_lookup_name.split('::').inject(Object) do |mod, class_name|
              #     mod.const_get(class_name)
              #   end # do
              # rescue => e
              #   @logger.debug("Encoding error 3: could not translate #{original_value} into enum. #{e}")
              #   raise e
              # end         
            end 
          end # if datahash_include
        end # do
      end # if meta
    end
    datahash
  end

  def pb2_encode_wrapper(event)
    data = pb2_encode(event.to_hash, @class_name)
    msg = @pb_builder.new(data)
    msg.serialize_to_string
  rescue NoMethodError => e
    @logger.debug("Encoding error 2. Probably mismatching protobuf definition. Required fields in the protobuf definition are: " + event.to_hash.keys.join(", ") + " and the timestamp field name must not include a @. ")
    raise e
  rescue => e
    @logger.debug("Encoding error 1: #{e.inspect}")
    raise e
  end



  def pb2_encode(datahash, class_name)    
    if datahash.is_a?(::Hash)
      # Preparation: the data cannot be encoded until certain criteria are met:
      # 1) remove @ signs from keys.
      # 2) convert timestamps and other objects to strings
      datahash = ::Hash[datahash.map{|(k,v)| [k.to_s.dup.gsub(/@/,''), (should_convert_to_string?(v) ? v.to_s : v)] }]
      
      # Check if any of the fields in this hash are protobuf classes and if so, create a builder for them.
      meta = @metainfo_messageclasses[class_name]
      if meta
        meta.map do | (k,c) |
          if datahash.include?(k)
            original_value = datahash[k]            
            datahash[k] = 
              if original_value.is_a?(::Array)
                # make this field an array/list of protobuf objects
                # value is a list of hashed complex objects, each of which needs to be protobuffed and
                # put back into the list.
                original_value.map { |x| pb2_encode(x, c) } 
                original_value
              else 
                proto_obj = pb2_create_instance(c)
                proto_obj.new(pb2_encode(original_value, c)) # this line is reached in the colourtest for an enum. Enums should not be instantiated. Should enums even be in the messageclasses? I dont think so! TODO bug
              end # if is array
          end # if datahash_include
        end # do
      end # if meta
    end
    datahash
  end


  def should_convert_to_string?(v)
    !(v.is_a?(Fixnum) || v.is_a?(::Hash) || v.is_a?(::Array) || [true, false].include?(v))
  end

  
  def pb2_create_instance(name)
    @logger.debug("Creating instance of " + name)
    name.split('::').inject(Object) { |n,c| n.const_get c }
  end


  def pb3_metadata_analyis(filename)
    regex_class_name = /\s*add_message "(?<name>.+?)" do\s+/ # TODO optimize both regexes for speed (negative lookahead)
    regex_pbdefs = /\s*(optional|repeated)(\s*):(?<name>.+),(\s*):(?<type>\w+),(\s*)(?<position>\d+)(, \"(?<enum_class>.*?)\")?/
    class_name = ""
    type = ""
    field_name = ""
    File.readlines(filename).each do |line|
      if ! (line =~ regex_class_name).nil? 
        class_name = $1
        @metainfo_messageclasses[class_name] = {}
        @metainfo_enumclasses[class_name] = {}
      end # if
      if ! (line =~ regex_pbdefs).nil?
        field_name = $1
        type = $2
        field_class_name = $4
        if type == "message"
          @metainfo_messageclasses[class_name][field_name] = field_class_name
        elsif type == "enum"
          @metainfo_enumclasses[class_name][field_name] = field_class_name
        end
      end # if
    end # readlines
    if class_name.nil?
      @logger.warn("Error 4: class name not found in file  " + filename)
      raise ArgumentError, "Invalid protobuf file: " + filename
    end
  rescue Exception => e
    @logger.warn("Error 3: unable to read pb definition from file  " + filename+ ". Reason: #{e.inspect}. Last settings were: class #{class_name} field #{field_name} type #{type}. Backtrace: " + e.backtrace.inspect.to_s)
    raise e
  end
      


  def pb2_metadata_analyis(filename)
    regex_class_start = /\s*set_fully_qualified_name \"(?<name>.+)\".*?/
    regex_enum_name = /\s*include ..ProtocolBuffers..Enum\s*/
    regex_pbdefs = /\s*(optional|repeated)(\s*):(?<type>.+),(\s*):(?<name>\w+),(\s*)(?<position>\d+)/
    # now we also need to find out which class it contains and the protobuf definitions in it.
    # We'll unfortunately need that later so that we can create nested objects.

    class_name = ""
    type = ""
    field_name = ""
    is_enum_class = false

    File.readlines(filename).each do |line|
      if ! (line =~ regex_enum_name).nil?
        is_enum_class= true
       end

      if ! (line =~ regex_class_start).nil?
        class_name = $1.gsub('.',"::").split('::').map {|word| word.capitalize}.join('::')
        if is_enum_class
          @metainfo_pb2_enumlist << class_name.downcase
        end
        is_enum_class= false # reset when next class starts
      end
      if ! (line =~ regex_pbdefs).nil?
        type = $1
        field_name = $2
        if type =~ /::/
          clean_type = type.gsub(/^:/,"")
          e = @metainfo_pb2_enumlist.include? clean_type.downcase
          
          if e
            if not @metainfo_enumclasses.key? class_name
              @metainfo_enumclasses[class_name] = {}
            end
            @metainfo_enumclasses[class_name][field_name] = clean_type
          else            
            if not @metainfo_messageclasses.key? class_name
              @metainfo_messageclasses[class_name] = {}
            end
            @metainfo_messageclasses[class_name][field_name] = clean_type
          end
        end
      end
    end
    if class_name.nil?
      @logger.warn("Error 4: class name not found in file  " + filename)
      raise ArgumentError, "Invalid protobuf file: " + filename
    end
  rescue LoadError => e
    raise ArgumentError.new("Could not load file: " + filename + ". Please try to use absolute pathes. Current working dir: " + Dir.pwd + ", loadpath: " + $LOAD_PATH.join(" "))
  rescue => e
    
    @logger.warn("Error 3: unable to read pb definition from file  " + filename+ ". Reason: #{e.inspect}. Last settings were: class #{class_name} field #{field_name} type #{type}. Backtrace: " + e.backtrace.inspect.to_s)
    raise e
  end
 

  def load_protobuf_definition(filename)
    if filename.end_with? ('.rb')
      if (Pathname.new filename).absolute?
        require filename
      else
        require_relative filename # needed for the test cases
        r = File.expand_path(File.dirname(__FILE__))
        filename = File.join(r, filename) # make the path absolute 
      end
     
      if @protobuf_version == 3
        pb3_metadata_analyis(filename)
      else
        pb2_metadata_analyis(filename)
      end
      
    else 
      @logger.warn("Not a ruby file: " + filename)
    end
  end


end # class LogStash::Codecs::Protobuf
