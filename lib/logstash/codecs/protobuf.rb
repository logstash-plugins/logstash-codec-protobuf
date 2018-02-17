# encoding: utf-8
require 'logstash/codecs/base'
require 'logstash/util/charset'
require 'google/protobuf' # for protobuf3
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers, for protobuf2

# This codec converts protobuf encoded messages into logstash events and vice versa. 
#
# Requires the protobuf definitions as ruby files. You can create those using the [ruby-protoc compiler](https://github.com/codekitchen/ruby-protocol-buffers).
# 
# The following shows a usage example for decoding events from a kafka stream:
# [source,ruby]
# kafka 
# {
#  zk_connect => "127.0.0.1"
#  topic_id => "your_topic_goes_here"
#  codec => protobuf 
#  {
#    class_name => "Animal::Unicorn"
#    include_path => ['/path/to/protobuf/definitions/UnicornProtobuf.pb.rb']
#  }
# }
#

class LogStash::Codecs::Protobuf < LogStash::Codecs::Base
  config_name 'protobuf'

  # Name of the class to decode.
  # If your protobuf definition contains modules, prepend them to the class name with double colons like so:
  # [source,ruby]
  # class_name => "Foods::Dairy::Cheese"
  # 
  # This corresponds to a protobuf definition starting as follows:
  # [source,ruby]
  # module Foods
  #    module Dairy
  #        class Cheese
  #            # here are your field definitions.
  # 
  # If your class references other definitions: you only have to add the main class here.
  config :class_name, :validate => :string, :required => true

  # List of absolute pathes to files with protobuf definitions. 
  # When using more than one file, make sure to arrange the files in reverse order of dependency so that each class is loaded before it is 
  # refered to by another.
  # 
  # Example: a class _Cheese_ referencing another protobuf class _Milk_
  # [source,ruby]
  # module Foods
  #   module Dairy
  #         class Cheese
  #            set_fully_qualified_name "Foods.Dairy.Cheese"
  #            optional ::Foods::Cheese::Milk, :milk, 1
  #            optional :int64, :unique_id, 2
  #            # here be more field definitions
  #
  # would be configured as
  # [source,ruby]
  # include_path => ['/path/to/protobuf/definitions/Milk.pb.rb','/path/to/protobuf/definitions/Cheese.pb.rb']
  #
  # When using the codec in an output plugin: 
  # * make sure to include all the desired fields in the protobuf definition, including timestamp. 
  #   Remove fields that are not part of the protobuf definition from the event by using the mutate filter.
  # * the @ symbol is currently not supported in field names when loading the protobuf definitions for encoding. Make sure to call the timestamp field "timestamp" 
  #   instead of "@timestamp" in the protobuf file. Logstash event fields will be stripped of the leading @ before conversion.
  #  
  config :include_path, :validate => :array, :required => true

  # Protocol buffer version switch. Set to false (default) for version 2. Please note that the behaviour for enums varies between the versions. 
  # For protobuf 2 you will get integer representations for enums, for protobuf 3 you'll get string representations due to a different converter library.
  # Recommendation: use the translate plugin to restore previous behaviour when upgrading.
  config :protobuf_version_3, :validate => :boolean, :required => true, :default=>false


  def register
    @pb_metainfo = {}
    include_path.each { |path| load_protobuf_definition(path) }
    if @protobuf_version_3      
      @pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup(class_name).msgclass
    else
      @pb_builder = pb2_create_instance(class_name)
    end
  end


  def decode(data)
    begin
      if @protobuf_version_3
        decoded = @pb_builder.decode(data.to_s)
        h = pb3_deep_to_hash(decoded)
      else
        decoded = @pb_builder.parse(data.to_s)
        h = decoded.to_hash        
      end
      yield LogStash::Event.new(h) if block_given?
    rescue => e
      @logger.warn("Couldn't decode protobuf: #{e.inspect}.")
      raise e
    end
  end # def decode


  def encode(event)
    if @protobuf_version_3
      protobytes = pb3_encode_wrapper(event)
    else
      protobytes = pb2_encode_wrapper(event)     
    end
     @on_event.call(event, protobytes)
  end # def encode


  private
  def pb3_deep_to_hash(input)
    if input.class.ancestors.include? Google::Protobuf::MessageExts # it's a protobuf class
      result = Hash.new
      input.to_hash.each {|key, value|
        result[key] = pb3_deep_to_hash(value) # the key is required for the class lookup of enums.
      }      
    elsif input.kind_of?(Array)
      result = []
      input.each {|value|
          result << pb3_deep_to_hash(value)
      }
    elsif input.instance_of? Symbol # is an Enum
      result = input.to_s.sub(':','')
    else
      result = input
    end
    result
  end

  def pb3_encode_wrapper(event)
    begin
      data = event.to_hash.inject({}){|x,(k,v)| x[k.gsub(/@/,'').to_sym] = (should_convert_to_string?(v) ? v.to_s : v); x} # TODO for nested classes this will have to be done recursively
      puts "pb3_encode_wrapper data: #{data}"
      pb_obj = @pb_builder.new(data)
      @pb_builder.encode(pb_obj)
    rescue ArgumentError => e
      @logger.debug("Encoding error 2. Probably mismatching protobuf definition. Required fields in the protobuf definition are: " + event.to_hash.keys.join(", ") + " and the timestamp field name must not include a @. ")
      raise e
    rescue => e
      @logger.debug("Couldn't generate protobuf: ${e}")
      raise e
    end
  end

  def pb2_encode_wrapper(event)
    begin
      data = pb2_encode(event.to_hash, @class_name)
      msg = @pb_builder.new(data)
      msg.serialize_to_string
    rescue NoMethodError => e
      @logger.debug("Encoding error 2. Probably mismatching protobuf definition. Required fields in the protobuf definition are: " + event.to_hash.keys.join(", ") + " and the timestamp field name must not include a @. ")
      raise e
    rescue => e
      @logger.debug("Encoding error 1: ${e}")
      raise e
    end
  end


  def pb2_encode(datahash, class_name)
    next unless datahash.is_a?(::Hash)

    # the data cannot be encoded until certain criteria are met:
    # 1) remove @ signs from keys.
    # 2) convert timestamps and other objects to strings
    datahash = ::Hash[datahash.map{|(k,v)| [k.to_s.dup.gsub(/@/,''), (should_convert_to_string?(v) ? v.to_s : v)] }]
    
    meta = @pb_metainfo[class_name] # gets a hash with member names and their protobuf class names
    if meta
      meta.map do | (k,typeinfo) |
        if datahash.include?(k)
          original_value = datahash[k] 
          proto_obj = pb2_create_instance(typeinfo)
          datahash[k] = 
            if original_value.is_a?(::Array)
              # make this field an array/list of protobuf objects
              # value is a list of hashed complex objects, each of which needs to be protobuffed and
              # put back into the list.
              original_value.map { |x| pb2_encode(x, typeinfo) } 
              original_value
            else 
              recursive_fix = pb2_encode(original_value, class_name)
              proto_obj.new(recursive_fix)
            end # if is array
        end # if datahash_include
      end # do
    end # if meta
    datahash
  end


  def should_convert_to_string?(v)
    !(v.is_a?(Fixnum) || v.is_a?(::Hash) || v.is_a?(::Array) || [true, false].include?(v))
  end

  
  def pb2_create_instance(name)
    begin
      @logger.debug("Creating instance of " + name)
      name.split('::').inject(Object) { |n,c| n.const_get c }
     end
  end


  def pb2_metadata_analyis(filename)
    require filename
    regex_class_name = /\s*class\s*(?<name>.+?)\s+/
    regex_module_name = /\s*module\s*(?<name>.+?)\s+/
    regex_pbdefs = /\s*(optional|repeated)(\s*):(?<type>.+),(\s*):(?<name>\w+),(\s*)(?<position>\d+)/
    # now we also need to find out which class it contains and the protobuf definitions in it.
    # We'll unfortunately need that later so that we can create nested objects.
    begin 
      class_name = ""
      type = ""
      field_name = ""
      classname_found = false
      File.readlines(filename).each do |line|
        if ! (line =~ regex_module_name).nil? && !classname_found # because it might be declared twice in the file
          class_name << $1 
          class_name << "::"
    
        end
        if ! (line =~ regex_class_name).nil? && !classname_found # because it might be declared twice in the file
          class_name << $1
          @pb_metainfo[class_name] = {}
          classname_found = true
        end
        if ! (line =~ regex_pbdefs).nil?
          type = $1
          field_name = $2
          if type =~ /::/
            @pb_metainfo[class_name][field_name] = type.gsub!(/^:/,"")
            
          end
        end
      end
    rescue Exception => e
      @logger.warn("error 3: unable to read pb definition from file  " + filename+ ". Reason: #{e.inspect}. Last settings were: class #{class_name} field #{field_name} type #{type}. Backtrace: " + e.backtrace.inspect.to_s)
    end
    if class_name.nil?
      @logger.warn("error 4: class name not found in file  " + filename)
    end    
  end

  def load_protobuf_definition(filename)
    begin
      if filename.end_with? ('.rb')
        @logger.debug("Including protobuf file: " + filename)
        require filename
        if @protobuf_version_3
          # todo read enum metadata
        else
          pb2_metadata_analyis(filename)
        end
      else 
        @logger.warn("Not a ruby file: " + filename)
      end
    end
  end


end # class LogStash::Codecs::Protobuf
