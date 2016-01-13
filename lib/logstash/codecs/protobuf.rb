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

  # remove 'set_fields' field
  config :remove_set_fields, :validate => :boolean, :default => true # TODO add documentation

  
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
    raise 'Encoder function not implemented yet for protobuf codec. Sorry!'
    # @on_event.call(event, event.to_s)
    # TODO integrate
  end # def encode



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
     formatted_key = key.to_s.gsub('@', '').to_sym
     next if remove_set_fields && formatted_key == :set_fields
     instance_var = decoded_object.instance_variable_get(key)

     results[formatted_key] =
         if instance_var.is_a?(::ProtocolBuffers::Message)
           extract_vars(instance_var)
         elsif instance_var.is_a?(Enumerable)
           instance_var.entries
         else
           instance_var
         end
   end
   results
  end

end # class LogStash::Codecs::Protobuf
