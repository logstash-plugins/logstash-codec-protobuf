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

  
  def register
    include_path.each { |path| require_pb_path(path) }
    @obj = create_object_from_name(class_name)
    @logger.debug("Protobuf files successfully loaded.")
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
    fields = prepare_event_for_protobuf(event)
    begin
      msg = @obj.new(fields)
      msg.serialize_to_string
    rescue NoMethodError
      @logger.debug("error 2: NoMethodError. Maybe mismatching protobuf definition. Required fields are: " + event.to_hash.keys.join(", "))
    end
  end # def generate_protobuf


  def prepare_event_for_protobuf(event)
    # 1) remove @ signs from keys 
    # 2) convert timestamps and other objects to strings
    Hash[event.to_hash.map{|(k,v)| [remove_atchar(k.to_s), (convert_to_string?(v) ? v.to_s : v)] }] 
    # TODO think about recursion for this. Maybe have a look at the way that the decoder traverses over the object hierarchy and copy that.
  end #prepare_event_for_protobuf

  def convert_to_string?(v)
    !(v.is_a?(Fixnum) || [true, false].include?(v))
  end

   
  def remove_atchar(key) # necessary for @timestamp fields and the likes. #TODO check again if this is really necessary once everything is finished and running stable.
    key.dup.gsub(/@/,'')
  end

  private
  def create_object_from_name(name)
    begin
      @logger.debug("Creating instance of " + name)
      return name.split('::').inject(Object) { |n,c| n.const_get c }
     end
  end


  def require_pb_path(dir_or_file)
    f = dir_or_file.end_with? ('.rb')
    begin
      if f
        @logger.debug("Including protobuf file: " + dir_or_file)
        require dir_or_file
      else 
        Dir[ dir_or_file + '/*.rb'].each { |file|
          @logger.debug("Including protobuf path: " + dir_or_file + "/" + file)
          require file 
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
        elsif instance_var.is_a?(Enumerable) # is a list
          instance_var.inject([]) { |h, v| h.push(extract_vars(v)); h }
        else
          instance_var
        end
     end
   results
  end

end # class LogStash::Codecs::Protobuf
