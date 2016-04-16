# encoding: utf-8
require 'logstash/codecs/base'
require 'logstash/util/charset'
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers

class LogStash::Codecs::Protobuf < LogStash::Codecs::Base
  config_name 'protobuf'

  # Required: list of strings containing directories or files with protobuf definitions
  config :include_path, :validate => :array, :required => true

  # Name of the class to decode
  config :class_name, :validate => :string, :required => true

  # For benchmarking only, not intended for public use: change encoder strategy. 
  # valid method names are:  encoder_strategy_1 (the others are not implemented yet)
  config :encoder_method, :validate => :string, :default => "encoder_strategy_1"

  def register
    if !@is_registered
      @pb_metainfo = {}
      include_path.each { |path| require_pb_path(path) }
      @obj = create_object_from_name(class_name)
      @logger.debug("Protobuf files successfully loaded.")
      @is_registered = true
    end
  end

  def decode(data)
    decoded = @obj.parse(data.to_s)
    results = extract_vars(decoded)
    yield LogStash::Event.new(results) if block_given?
  end # def decode

  def encode(event)
    protobytes = generate_protobuf(event)
    @on_event.call(event, protobytes)
  end # def encode

  private
  def generate_protobuf(event)  
    meth = self.method(encoder_method)
    data = meth.call(event, @class_name) # call the prefered method
    begin
      msg = @obj.new(data)
      msg.serialize_to_string
    rescue NoMethodError
      @logger.debug("error 2: NoMethodError. Maybe mismatching protobuf definition. Required fields are: " + event.to_hash.keys.join(", "))
    end
  end

  def encoder_strategy_1(event, class_name)
    _encoder_strategy_1(event.to_hash, class_name)

  end

  def _encoder_strategy_1(datahash, class_name)
  # see description of strategies above.
    fields = clean_hash_keys(datahash)
    fields = flatten_hash_values(fields) # TODO we could merge this and the above method back into one to save one iteration, but how are we going to name it?
    meta = get_complex_types(class_name) # returns a hash with member names and their protobuf class names
    meta.map do | (k,typeinfo) |
      if fields.include?(k)
        original_value = fields[k] 
        proto_obj = create_object_from_name(typeinfo)
        fields[k] = 
          if original_value.is_a?(::Array) 
            ecs1_list_helper(original_value, proto_obj, typeinfo) 
          else 
            recursive_fix = _encoder_strategy_1(original_value, class_name)
            proto_obj.new(recursive_fix)
          end # if is array
      end

    end 
    
    fields
  end

  def ecs1_list_helper(value, proto_obj, class_name)
    # make this field an array/list of protobuf objects
    # value is a list of hashed complex objects, each of which needs to be protobuffed and
    # put back into the list.
    List[value.each do |x| 
      y = _encoder_strategy_1(x, class_name)
      proto_obj.new(y)
    end
    ] 
  end

  def flatten_hash_values(datahash)
    # 2) convert timestamps and other objects to strings
    next unless datahash.is_a?(::Hash)
    
    Hash[datahash.map{|(k,v)| [k, (convert_to_string?(v) ? v.to_s : v)] }] 
  end

  def clean_hash_keys(datahash)
    # 1) remove @ signs from keys 
    next unless datahash.is_a?(::Hash)
    
    Hash[datahash.map{|(k,v)| [remove_atchar(k.to_s), v] }] 
  end #clean_hash_keys

  def convert_to_string?(v)
    !(v.is_a?(Fixnum) || v.is_a?(::Hash) || v.is_a?(::Array) || [true, false].include?(v))
  end

   
  def remove_atchar(key) # necessary for @timestamp fields and the likes. Protobuf definition doesn't handle @ in field names well.
    key.dup.gsub(/@/,'')
  end

  private
  def create_object_from_name(name)
    begin
      @logger.debug("Creating instance of " + name)
      name.split('::').inject(Object) { |n,c| n.const_get c }
     end
  end

  def get_complex_types(class_name)
    @pb_metainfo[class_name]
  end

  def require_with_metadata_analysis(filename)
    require filename
    regex_class_name = /\s*class\s*(?<name>.+?)\s+/
    regex_module_name = /\s*module\s*(?<name>.+?)\s+/
    regex_pbdefs = /\s*(optional|repeated)(\s*):(?<type>.+),(\s*):(?<name>\w+),(\s*)(?<position>\d+)/
    # now we also need to find out which class it contains and the protobuf definitions in it.
    # We'll unfortunately need that later so that we can create nested objects.
    begin 
      class_name = ""
      classname_found = false
      File.readlines(filename).each do |line|
        if ! (line =~ regex_module_name).nil?
          class_name << $1 
          class_name << "::"
        end
        if ! (line =~ regex_class_name).nil?
          if !classname_found # because it might be declared twice in the file
            class_name << $1
            @pb_metainfo[class_name] = {}
            classname_found = true
          end
        end
        if ! (line =~ regex_pbdefs).nil?
          type = $1
          field_name = $2
          if type =~ /::/
            @pb_metainfo[class_name][field_name] = type.gsub!(/^:/,"")
            
          end
        end
      end
    rescue
      @logger.warn("error 3: unable to read pb definition from file  " + filename)
    end
    if class_name.nil?
      @logger.warn("error 3: unable to read pb definition from file  " + filename)
    end 
  end

  def require_pb_path(dir_or_file)
    f = dir_or_file.end_with? ('.rb')
    begin
      if f
        @logger.debug("Including protobuf file: " + dir_or_file)
        require_with_metadata_analysis dir_or_file
      else 
        Dir[ dir_or_file + '/*.rb'].each { |file|
          @logger.debug("Including protobuf path: " + dir_or_file + "/" + file)
          require_with_metadata_analysis file 
        }
      end
    end
  end


  def extract_vars(decoded_object)
    return {} if decoded_object.nil?
    results = {}
    decoded_object.instance_variables.each do |key|
      formatted_key = key.to_s.gsub('@', '')
      next if (formatted_key == :set_fields || formatted_key == "set_fields")
      instance_var = decoded_object.instance_variable_get(key)

      results[formatted_key] =
        if instance_var.is_a?(::ProtocolBuffers::Message) 
          extract_vars(instance_var)
        elsif instance_var.is_a?(::Hash)
          instance_var.inject([]) { |h, (k, v)| h[k.to_s] = extract_vars(v); h }
        elsif instance_var.is_a?(Enumerable) # is a list/array
          instance_var.inject([]) { |h, v| h.push(extract_vars(v)); h }
        else
          instance_var
        end
     end
   results
  end

end # class LogStash::Codecs::Protobuf
