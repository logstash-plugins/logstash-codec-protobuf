# encoding: utf-8
require "logstash/codecs/base"
require "logstash/util/charset"
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers

class LogStash::Codecs::Protobuf < LogStash::Codecs::Base
  config_name "protobuf"

  # Required: list of strings containing directories or files with protobuf definitions
  config :include_path, :validate => :array, :required => true

  # Name of the class to decode
  config :class_name, :validate => :string, :required => true

  # remove 'set_fields' field
  config :remove_set_fields, :validate => :boolean, :default => true # TODO add documentation

  
  public
  def register
    @include_path.each{|path| require_pb_path(path) }
    @obj = create_object_from_name(@class_name)
    
  end


  private
  def create_object_from_name(name)
    begin
      c = name.split("::").inject(Object) { |n,c| n.const_get c }
      return c
    end
  end

  private 
  def debug(message)
    begin
      if @debug 
        @logger.debug(message)
      end
    end
  end

  private 
  def require_pb_path(dir_or_file)
    f = dir_or_file.end_with? (".rb")
    begin
      if f
        require dir_or_file
      else 
        Dir[ dir_or_file + "/*.rb"].each { |file| 
          require file 
        }
      end
    end
  end

  private
  def extract_variables(decoded_object)
    begin
      result_hash = {}
      if decoded_object.nil?
        return result_hash
      end
      decoded_object.instance_variables.map do |ivar|
        varname = ivar.to_s
        key = varname.gsub("@","")
        value = decoded_object.instance_variable_get("#{ivar}")
        recurse = value.is_a? (::ProtocolBuffers::Message)  # object is not a primitive scalar
        is_iterable |= value.is_a? Enumerable # value.respond_to? :each # object is an array
        if recurse
          result_hash[key] = extract_variables(value)
        elsif is_iterable
          tmp = []
          value.each do | nested |
            tmp.push(nested)
          end
          result_hash[key] = tmp
        else
          result_hash[key] = value
        end
      end
      if remove_set_fields
        return result_hash.except("set_fields") # todo try to do this before the object is handed to this method
      else
        return result_hash
      end      
    end
  end





  public
  def decode(data)
    decoded = @obj.parse(data.to_s)
    results = extract_variables(decoded)
    event = LogStash::Event.new(results)  
    yield event
    
  end # def decode

  public
  def encode(event)
    raise "Encoder function not implemented yet for protobuf codec. Sorry!"
    # @on_event.call(event, event.to_s)
    # TODO integrate
  end # def encode

end # class LogStash::Codecs::Protobuf
