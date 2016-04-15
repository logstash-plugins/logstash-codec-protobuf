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
    print fields # TODO remove
    begin
      msg = @obj.new(fields) # TODO for some reason this is nil.
      msg.serialize_to_string
    rescue NoMethodError
      @logger.debug("error 2: NoMethodError. Maybe mismatching protobuf definition.")
    end
  end # def generate_protobuf

  private
  def prepare_event_for_protobuf(event)
    Hash[event.to_hash.map{|(k,v)| [remove_atchar(k.to_s), (v.is_a?(Fixnum) ? v : v.to_s)] }] 
    # TODO make this work. Timestamp and other objects should be casted to string, numerics not, also not booleans. maybe check for object instead
    # take that from decoder maybe. Also think about recursion.
  end #prepare_event_for_protobuf

  private 
  def remove_atchar(key) # necessary for @timestamp fields and the likes.
    return key.dup.gsub(/@/,'')
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
