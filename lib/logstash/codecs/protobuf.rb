# encoding: utf-8
require 'logstash/codecs/base'
require 'logstash/util/charset'
require 'google/protobuf' # for protobuf3
require 'google/protobuf/struct_pb'
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers, for protobuf2


# Monkey-patch the `Google::Protobuf::DescriptorPool` with a mutex for exclusive
# access.
#
# The DescriptorPool instance is not thread-safe when loading protobuf
# definitions. This can cause unrecoverable errors when registering multiple
# concurrent pipelines that try to register the same dependency. The
# DescriptorPool instance is global to the JVM and shared among all pipelines.
class << Google::Protobuf::DescriptorPool
  def with_lock
    if !@mutex
      @mutex = Mutex.new
    end

    return @mutex
  end
end

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

  # Relative path to the ruby file that contains class_name
  #
  # Relative path (from `protobuf_root_directory`) that holds the definition of the class specified in
  # `class_name`.
  #
  # `class_file` and `include_path` cannot be used at the same time.
  config :class_file, :validate => :string, :default => '', :required => false

  # Absolute path to the root directory that contains all referenced/used dependencies
  # of the main class (`class_name`) or any of its dependencies.
  #
  # For instance:
  #
  # pb3
  #   ├── header
  #   │   └── header_pb.rb
  #   ├── messageA_pb.rb
  #
  # In this case `messageA_pb.rb` has an embedded message from `header/header_pb.rb`.
  # If `class_file` is set to `messageA_pb.rb`, and `class_name` to
  # `MessageA`, `protobuf_root_directory` must be set to `/path/to/pb3`, which includes
  #  both definitions.
  config :protobuf_root_directory, :validate => :string, :required => false

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
  # `class_file` and `include_path` cannot be used at the same time.
  config :include_path, :validate => :array, :default => [], :required => false

  # Protocol buffer version switch. Defaults to version 2. Please note that the behaviour for enums varies between the versions.
  # For protobuf 2 you will get integer representations for enums, for protobuf 3 you'll get string representations due to a different converter library.
  # Recommendation: use the translate plugin to restore previous behaviour when upgrading.
  config :protobuf_version, :validate => [2,3], :default => 2, :required => true

  # To tolerate faulty messages that cannot be en/decoded, set this to false. Otherwise the pipeline will stop upon encountering a non decipherable message.
  config :stop_on_error, :validate => :boolean, :default => false, :required => false

  # Instruct the encoder to attempt converting data types to match the protobuf definitions. Available only for protobuf version 3.
  config :pb3_encoder_autoconvert_types, :validate => :boolean, :default => true, :required => false

  # Add meta information to `[@metadata][pb_oneof]` about which classes were chosen for [oneof](https://developers.google.com/protocol-buffers/docs/proto3#oneof) fields.
  # Example values: for the protobuf definition
  # ```    oneof :horse_type do
  #          optional :unicorn, :message, 2, "FantasyUnicorn"
  #          optional :pegasus, :message, 3, "FantasyPegasus"
  #        end
  # ```
  # the field `[@metadata][pb_oneof][horse_type]` will be set to either `pegasus` or `unicorn`.
  # Available only for protobuf version 3.
  config :pb3_set_oneof_metainfo, :validate => :boolean, :default => false, :required => false


  attr_reader :execution_context

  # id of the pipeline whose events you want to read from.
  def pipeline_id
    respond_to?(:execution_context) && !execution_context.nil? ? execution_context.pipeline_id : "main"
  end

  def register
    @metainfo_messageclasses = {}
    @metainfo_enumclasses = {}
    @metainfo_pb2_enumlist = []
    @pb3_typeconversion_tag = "_protobuf_type_converted"

    if @include_path.length > 0 and not class_file.strip.empty?
      raise LogStash::ConfigurationError, "Cannot use `include_path` and `class_file` at the same time"
    end

    if @include_path.length == 0 and class_file.strip.empty?
      raise LogStash::ConfigurationError, "Need to specify `include_path` or `class_file`"
    end

    should_register = Google::Protobuf::DescriptorPool.generated_pool.lookup(class_name).nil?

    unless @protobuf_root_directory.nil? or @protobuf_root_directory.strip.empty?
      if !$LOAD_PATH.include? @protobuf_root_directory and should_register
        $LOAD_PATH.unshift(@protobuf_root_directory)
      end
    end

    @class_file = "#{@protobuf_root_directory}/#{@class_file}" unless (Pathname.new @class_file).absolute? or @class_file.empty?
    # exclusive access while loading protobuf definitions
    Google::Protobuf::DescriptorPool.with_lock.synchronize do
      # load from `class_file`
      load_protobuf_definition(@class_file) if should_register and !@class_file.empty?
      # load from `include_path`
      include_path.each { |path| load_protobuf_definition(path) } if include_path.length > 0 and should_register
      if @protobuf_version == 3
        @pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup(class_name).msgclass
      else
        @pb_builder = pb2_create_instance(class_name)
      end
    end
  end

  # Pipelines using this plugin cannot be reloaded.
  # https://github.com/elastic/logstash/pull/6499
  #
  # The DescriptorPool instance registers the protobuf classes (and
  # dependencies) as global objects. This makes it very difficult to reload a
  # pipeline, because `class_name` and all of its dependencies are already
  # registered.
  def reloadable?
    return false
  end

  def decode(data)
    if @protobuf_version == 3
      decoded = @pb_builder.decode(data.to_s)
      hashed, meta = pb3_to_hash(decoded)
    else # version = 2
      decoded = @pb_builder.parse(data.to_s)
      hashed = decoded.to_hash
    end
    e = LogStash::Event.new(hashed)
    if @protobuf_version == 3 and @pb3_set_oneof_metainfo
      e.set("[@metadata][pb_oneof]", meta)
    end
    yield e if block_given?
  rescue => ex
    @logger.warn("Couldn't decode protobuf: #{ex.inspect}")
    if @stop_on_error
      raise ex
    else # keep original message so that the user can debug it.
      yield LogStash::Event.new(
        "message" => data, "tags" => ["_protobufdecodefailure"],
        "decoder_exception" => "#{ex.inspect}")
    end
  end # def decode


  def encode(event)
    if @protobuf_version == 3
      protobytes = pb3_encode(event)
    else
      protobytes = pb2_encode(event)
    end
    unless protobytes.nil? or protobytes.empty?
      @on_event.call(event, protobytes)
    end
  end # def encode


  # Get the builder class for any given protobuf object from the descriptor pool
  # Exposed for testing
  # @param [Object] pb_obj The pb object instance to do the lookup for
  # @return [Object] The pb builder class
  def pb3_class_for_name(pb_obj)
    Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_obj.class.descriptor.name)
  end

  private

  # Helper function for debugging: print data types for fields of a hash
  def print_types(hashy, i = 0)
    hashy.each do |key, value|
      puts ws(i) + "#{key} " + value.class.name
      if value.is_a? ::Hash
        print_types(value, i + 1)
      end
      if value.is_a? ::Array
        value.each do |v|
          puts ws(i + 1) + "" + v.class.name
          if v.is_a? ::Hash
            print_types(v, i + 2)
          end
        end
      end
    end
  end

  # Helper function for debugging: indent print statements based on recursion level
  def ws(i)
    "   " * i
  end

  
  # Converts the pb class to a hash, including its nested objects. 
  # @param [Object] input The pb class or any of its nested data structures
  # @param [Numeric] i Level of recursion, needed only for whitespace indentation in debug output
  # @return [Hash, Hash] The converted data as a hash + meta information about the one-of choices.
  def pb3_to_hash(input, i = 0)
    meta = {}
    case input
    when Google::Protobuf::Struct
      result = JSON.parse input.to_json({
        :preserve_proto_fieldnames => true,
        :emit_defaults => true
      })
    when Google::Protobuf::MessageExts # it's a protobuf class
      result = Hash.new
      input.clone().to_h.keys.each {|key|
        # 'class' is a reserved word so we cannot send() it to the pb object. 
        # It would give the pb definition class instead of the value of a field of such name. 
        if key.to_s == "class"
          value = input[key]
        else
          value = input.send(key)
        end
        unless value.nil?
          r, m = pb3_to_hash(value, 1 + i)
          result[key.to_s] = r unless r.nil?
          meta[key] = m unless m.empty?
        end
      }
      result, m = oneof_clean(result, input, i)
      meta = meta.merge(m) unless m.empty?
    when ::Array
    when Google::Protobuf::RepeatedField
      result = []
      meta = []
      input.each {|value|
        r, m = pb3_to_hash(value, 1 + i)
        result << r unless r.nil?
        meta << m unless r.nil?
      }
    when ::Hash
    when Google::Protobuf::Map
      result = {}
      input.each {|key, value|
        r, m = pb3_to_hash(value, 1 + i)
        result[key.to_s] = r unless r.nil?
        meta[key] = m unless m.empty?
      }
    when Symbol # is an Enum
      result = input.to_s.sub(':','')
    else # any other scalar
      result = input
    end
    return result, meta
  end


  # For one-of options, remove the non-chosen options.
  # @param [Hash] datahash The data hash including all options for each one-of field
  # @param [Object] pb_obj The protobuf class from which datahash was created
  # @param [Numeric] i Level of recursion, needed only for whitespace indentation in debug output
  # @return [Hash, Hash] The reduced data as a hash + meta information about the one-of choices.
  def oneof_clean(datahash, pb_obj, i = 0) 
    # If a field is part of a one-of then it must only be set if it's the selected option.
    # In codec versions <= 1.2.x this was not the case. The .to_h delivered default values 
    # for every one-of option regardless of which one had been chosen, instead of respecting the XOR relation between them.
    # The selected option's field name can be queried from input[parent_field] 
    # where parent_field is the name of the one-of field outside the option list. 
    # It's unclear though how to identify a) if a field is part of a one-of struct
    # because the class of the chosen option will always be a scalar, 
    # and b) the name of the parent field. 
    # As a workaround we look up the names of the 'parent fields' for this class and then the chosen options for those.
    # Then we remove the other options which weren't set by the producer.
    pb_class = pb3_class_for_name(pb_obj)
    meta = {}
    unless pb_class.nil?
      pb_class.msgclass.descriptor.each_oneof { |field|
        # Find out which one-of option has been set
        chosen = pb_obj.send(field.name).to_s
        # Go through the options and remove the names of the non-chosen fields from the hash
        # Whacky solution, better ideas are welcome.
        field.each { | group_option |
          if group_option.name != chosen
            key = group_option.name
            datahash.delete(key)
          end
        }
        meta[field.name.to_s] = chosen        
      }
    end # unless
    return datahash, meta
  end


  def pb3_encode(event)
    datahash = event.to_hash
    is_recursive_call = !event.get('tags').nil? and event.get('tags').include? @pb3_typeconversion_tag
    if is_recursive_call
      datahash = pb3_remove_typeconversion_tag(datahash)
    end
    datahash = pb3_prepare_for_encoding(datahash)
    if datahash.nil?
      @logger.warn("Protobuf encoding error 4: empty data for event #{event.to_hash}")
    end
    if @pb_builder.nil?
      @logger.warn("Protobuf encoding error 5: empty protobuf builder for class #{@class_name}")
    end
    pb_obj = @pb_builder.new(datahash)
    @pb_builder.encode(pb_obj)
  rescue ArgumentError => e
    k = event.to_hash.keys.join(", ")
    @logger.warn("Protobuf encoding error 1: Argument error (#{e.inspect}). Reason: probably mismatching protobuf definition. \
      Required fields in the protobuf definition are: #{k} and fields must not begin with @ sign. The event has been discarded.")
    nil
  rescue TypeError => e
    pb3_handle_type_errors(event, e, is_recursive_call, datahash)
    nil
  rescue => e
    @logger.warn("Protobuf encoding error 3: #{e.inspect}. Event discarded. Input data: #{datahash}. The event has been discarded. Backtrace: #{e.backtrace}")
    nil
  end


  def pb3_handle_type_errors(event, e, is_recursive_call, datahash)
    begin
      if is_recursive_call
        @logger.warn("Protobuf encoding error 2.1: Type error (#{e.inspect}). Some types could not be converted. The event has been discarded. Type mismatches: #{mismatches}.")
      else
        if @pb3_encoder_autoconvert_types
          msg = "Protobuf encoding error 2.2: Type error (#{e.inspect}). Will try to convert the data types. Original data: #{datahash}"
          @logger.warn(msg)
          mismatches = pb3_get_type_mismatches(datahash, "", @class_name)

          event = pb3_convert_mismatched_types(event, mismatches)
          # Add a (temporary) tag to handle the recursion stop
          pb3_add_tag(event, @pb3_typeconversion_tag )
          pb3_encode(event)
        else
          @logger.warn("Protobuf encoding error 2.3: Type error (#{e.inspect}). The event has been discarded. Try setting pb3_encoder_autoconvert_types => true for automatic type conversion.")
        end
      end
    rescue TypeError => e
      if @pb3_encoder_autoconvert_types
        @logger.warn("Protobuf encoding error 2.4.1: (#{e.inspect}). Failed to convert data types. The event has been discarded. original data: #{datahash}")
      else
        @logger.warn("Protobuf encoding error 2.4.2: (#{e.inspect}). The event has been discarded.")
      end
      if @stop_on_error
        raise e
      end
      nil
    rescue => ex
      @logger.warn("Protobuf encoding error 2.5: (#{e.inspect}). The event has been discarded. Auto-typecasting was on: #{@pb3_encoder_autoconvert_types}")
      if @stop_on_error
        raise ex
      end
      nil
    end
  end # pb3_handle_type_errors


  def pb3_get_type_mismatches(data, key_prefix, pb_class)
    mismatches = []
    data.to_h.each do |key, value|
        expected_type = pb3_get_expected_type(key, pb_class)
        r = pb3_compare_datatypes(value, key, key_prefix, pb_class, expected_type)
        mismatches.concat(r)
    end # data.each
    mismatches
  end


  def pb3_get_expected_type(key, pb_class)
    pb_descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_class)
    if !pb_descriptor.nil?
      pb_builder = pb_descriptor.msgclass
      pb_obj = pb_builder.new({})
      v = pb_obj.send(key)
      if !v.nil?
        v.class
      else
        nil
      end
    end
  end


  def pb3_compare_datatypes(value, key, key_prefix, pb_class, expected_type)
    mismatches = []
    if value.nil?
      is_mismatch = false
    else
      case value
      when ::Hash, Google::Protobuf::MessageExts
        is_mismatch = false
        descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_class).lookup(key)
        if !descriptor.subtype.nil?
          class_of_nested_object = pb3_get_descriptorpool_name(descriptor.subtype.msgclass)
          new_prefix = "#{key}."
          recursive_mismatches = pb3_get_type_mismatches(value, new_prefix, class_of_nested_object)
          mismatches.concat(recursive_mismatches)
        end
      when ::Array
        expected_type = pb3_get_expected_type(key, pb_class)
        is_mismatch = (expected_type != Google::Protobuf::RepeatedField)
        child_type = Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_class).lookup(key).type
        value.each_with_index  do | v, i |
          new_prefix = "#{key}."
          recursive_mismatches = pb3_compare_datatypes(v, i.to_s, new_prefix, pb_class, child_type)
          mismatches.concat(recursive_mismatches)
          is_mismatch |= recursive_mismatches.any?
        end # do
      else # is scalar data type

        is_mismatch = ! pb3_is_scalar_datatype_match(expected_type, value.class)
      end # if
    end # if value.nil?

    if is_mismatch
      mismatches << {"key" => "#{key_prefix}#{key}", "actual_type" => value.class, "expected_type" => expected_type, "value" => value}
    end
    mismatches
  end

  def pb3_remove_typeconversion_tag(data)
    # remove the tag that we added to the event because
    # the protobuf definition might not have a field for tags
    data['tags'].delete(@pb3_typeconversion_tag)
    if data['tags'].length == 0
      data.delete('tags')
    end
    data
  end

  def pb3_get_descriptorpool_name(child_class)
    # make instance
    inst = child_class.new
    # get the lookup name for the Descriptorpool
    inst.class.descriptor.name
  end

  def pb3_is_scalar_datatype_match(expected_type, actual_type)
    if expected_type == actual_type
      true
    else
      e = expected_type.to_s.downcase.to_sym
      a = actual_type.to_s.downcase.to_sym
      case e
      # when :string, :integer
      when :string
          a == e
      when :integer
          a == e
      when :float
          a == :float || a == :integer
      end
    end
  end


  def pb3_convert_mismatched_types_getter(struct, key)
    if struct.is_a? ::Hash
      struct[key]
    else
      struct.get(key)
    end
  end

  def pb3_convert_mismatched_types_setter(struct, key, value)
    if struct.is_a? ::Hash
      struct[key] = value
    else
      struct.set(key, value)
    end
    struct
  end

  def pb3_add_tag(event, tag )
    if event.get('tags').nil?
        event.set('tags', [tag])
    else
      existing_tags = event.get('tags')
      event.set("tags", existing_tags << tag)
    end
  end


  # Due to recursion on nested fields in the event object this method might be given an event (1st call) or a hash (2nd .. nth call)
  # First call will be the event object, child objects will be hashes.
  def pb3_convert_mismatched_types(struct, mismatches)
    mismatches.each do | m |
        key = m['key']
        expected_type = m['expected_type']
        actual_type = m['actual_type']
        if key.include? "." # the mismatch is in a child object
            levels = key.split(/\./) # key is something like http_user_agent.minor_version and needs to be splitted.
            key = levels[0]
            sub_levels = levels.drop(1).join(".")
            new_mismatches = [{"key"=>sub_levels, "actual_type"=>m["actual_type"], "expected_type"=>m["expected_type"]}]
            value = pb3_convert_mismatched_types_getter(struct, key)
            new_value = pb3_convert_mismatched_types(value, new_mismatches)
            struct = pb3_convert_mismatched_types_setter(struct, key, new_value )
        else
            value = pb3_convert_mismatched_types_getter(struct, key)
            begin
                case expected_type.to_s
                when "Integer"
                    case actual_type.to_s
                    when "String"
                        new_value = value.to_i
                    when "Float"
                        if value.floor == value # convert values like 2.0 to 2, but not 2.1
                          new_value = value.to_i
                        end
                    end
                when "String"
                    new_value = value.to_s
                when "Float"
                    new_value = value.to_f
                when "Boolean","TrueClass", "FalseClass"
                    new_value = value.to_s.downcase == "true"
                end
                if !new_value.nil?
                  struct = pb3_convert_mismatched_types_setter(struct, key, new_value )
                end
            rescue Exception => ex
                @logger.debug("Protobuf encoding error 5: Could not convert types for protobuf encoding: #{ex}")
            end
        end # if key contains .
    end # mismatches.each
    struct
  end


  def pb3_prepare_for_encoding(datahash)
    # 0) Remove empty fields.
    datahash = datahash.select { |key, value| !value.nil? }

    # Preparation: the data cannot be encoded until certain criteria are met:
    # 1) remove @ signs from keys.
    # 2) convert timestamps and other objects to strings
    datahash = datahash.inject({}){|x,(k,v)| x[k.gsub(/@/,'').to_sym] = (should_convert_to_string?(v) ? v.to_s : v); x}

    datahash.each do |key, value|
      datahash[key] = pb3_prepare_for_encoding(value) if value.is_a?(Hash)
    end

    datahash
  end


  def pb2_encode(event)
    data = pb2_prepare_for_encoding(event.to_hash, @class_name)
    msg = @pb_builder.new(data)
    msg.serialize_to_string
  rescue NoMethodError => e
    @logger.warn("Encoding error 2. Probably mismatching protobuf definition. Required fields in the protobuf definition are: " + event.to_hash.keys.join(", ") + " and the timestamp field name must not include a @. ")
    raise e
  rescue => e
    @logger.warn("Encoding error 1: #{e.inspect}")
    raise e
  end


  def pb2_prepare_for_encoding(datahash, class_name)
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
                original_value.map { |x| pb2_prepare_for_encoding(x, c) }
                original_value
              else
                proto_obj = pb2_create_instance(c)
                proto_obj.new(pb2_prepare_for_encoding(original_value, c)) # this line is reached in the colourtest for an enum. 
                # Enums should not be instantiated. Should enums even be in the messageclasses? I dont think so!
              end # if is array
          end # if datahash_include
        end # do
      end # if meta
    end
    datahash
  end


  def should_convert_to_string?(v)
    !(v.is_a?(Integer) || v.is_a?(Float) || v.is_a?(::Hash) || v.is_a?(::Array) || [true, false].include?(v))
  end


  def pb2_create_instance(name)
    @logger.debug("Creating instance of " + name)
    name.split('::').inject(Object) { |n,c| n.const_get c }
  end


  def pb3_metadata_analyis(filename)
    regex_class_name = /\s*add_message "(?<name>.+?)" do\s+/
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
      @logger.error("Error 4: class name not found in file  " + filename)
      raise ArgumentError, "Invalid protobuf file: " + filename
    end
  rescue Exception => e
    @logger.error("Error 3: unable to read pb definition from file  " + filename+ ". Reason: #{e.inspect}. Last settings were: class #{class_name} field #{field_name} type #{type}. Backtrace: " + e.backtrace.inspect.to_s)
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
      # Add to the loading path of the protobuf definitions
      if (Pathname.new filename).absolute?
        begin
          require filename
        rescue Exception => e
          @logger.error("Unable to load file: #{filename}. Reason: #{e.inspect}")
          raise e
        end
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
