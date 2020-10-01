# encoding: utf-8
require 'logstash/codecs/base'
require 'logstash/util/charset'
require 'google/protobuf' # for protobuf3
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

  # To tolerate faulty messages that cannot be decoded, set this to false. Otherwise the pipeline will stop upon encountering a non decipherable message.
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

  # Encoder should ignore fields which are present in the event but not in the pb definition.
  # When setting to false, invalid events will be discarded and an error will be logged.
  # Available only for protobuf version 3.
  config :pb3_encoder_drop_unknown_fields, :validate => :boolean, :default => true, :required => false


  attr_reader :execution_context

  # id of the pipeline whose events you want to read from.
  def pipeline_id
    respond_to?(:execution_context) && !execution_context.nil? ? execution_context.pipeline_id : "main"
  end

  def register
    @metainfo_messageclasses = {}
    @metainfo_enumclasses = {}
    @metainfo_existingfields = {}
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

    if @protobuf_version == 3
      include_path.each { |path| pb3_metadata_analyis(path) } if include_path.length > 0
      pb3_metadata_analyis(@class_file) if !@class_file.empty?
    else
      include_path.each { |path| pb2_metadata_analyis(path) } if include_path.length > 0
      pb2_metadata_analyis(@class_file) if !@class_file.empty?
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
      if @pb3_set_oneof_metainfo
        meta = pb3_get_oneof_metainfo(decoded, @class_name)
      end
      h = pb3_deep_to_hash(decoded)
    else
      decoded = @pb_builder.parse(data.to_s)
      h = decoded.to_hash
    end
    e = LogStash::Event.new(h)
    if @protobuf_version == 3 and @pb3_set_oneof_metainfo
      e.set("[@metadata][pb_oneof]", meta)
    end
    yield e if block_given?
  rescue => ex
    @logger.warn("Couldn't decode protobuf: #{ex.inspect}.")
    if stop_on_error
      raise ex
    else # keep original message so that the user can debug it.
      yield LogStash::Event.new("message" => data, "tags" => ["_protobufdecodefailure"])
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

  def pb3_encode(event)
    datahash = event.to_hash
    is_recursive_call = !event.get('tags').nil? and event.get('tags').include? @pb3_typeconversion_tag
    if is_recursive_call
      datahash = pb3_remove_typeconversion_tag(datahash)
    end
    datahash = pb3_prepare_for_encoding(datahash, @class_name, [])
    if datahash.nil?
      @logger.warn("PB3 encoder err 1.1: empty data for event #{event.to_hash}")
    end
    if @pb_builder.nil?
      @logger.warn("PB3 encoder err 1.2: empty protobuf builder for class #{@class_name}")
    end
    puts "Hello 3" # TODO remove
    pb_obj = @pb_builder.new(datahash)
    puts "Hello 4" # TODO remove
    @pb_builder.encode(pb_obj)
  rescue ArgumentError => e
    puts "Hello 11 #{e} #{datahash}" # TODO remove
    k = event.to_hash.keys.join(", ")
    msg = "PB3 encoder err 1.3: Argument error (#{e.inspect}). Reason: probably mismatching protobuf definition. Required fields in the protobuf definition are: #{k}. Fields must not begin with @ sign. The event has been discarded."
    @logger.warn(msg)
    nil
  rescue TypeError => e
    puts "Hello 5" # TODO remove
    if is_recursive_call
      puts "Hello 5.1" # TODO remove
      @logger.warn("PB3 encoder err 1.4: Type error (#{e.inspect}). Some types could not be converted. The event has been discarded. Original data: #{datahash}")
      nil
    else
      puts "Hello 5.2" # TODO remove
      pb3_handle_type_errors(event, datahash)
    end
  rescue => e
    puts "Hello 10 #{e}" # TODO remove
    @logger.warn("PB3 encoder err 1.5: #{e}. Event dropped. Input data: #{datahash}. Backtrace: #{e.backtrace}")
    nil
  end

  def pb3_handle_type_errors(event, datahash)
    puts "Hello 6" # TODO remove
    begin
      if @pb3_encoder_autoconvert_types
        puts "Hello 7 incoming #{datahash}" # TODO remove
        mismatches = pb3_get_type_mismatches(datahash, "", @class_name)
        puts "Hello 8 #{mismatches}" # TODO remove
        event = pb3_convert_mismatched_types(event, mismatches)
        puts "Hello 9 #{event.to_hash}" # TODO remove
        # Add a (temporary) tag to handle the recursion stop
        pb3_add_tag(event, @pb3_typeconversion_tag )
        pb3_encode(event)
      else
        @logger.warn("PB3 encoder err 2.3: Type error (#{e.inspect}). The event has been discarded. Try setting pb3_encoder_autoconvert_types => true for automatic type conversion.")
        nil
      end
    rescue TypeError => e
      if @pb3_encoder_autoconvert_types
        @logger.warn("PB3 encoder err 2.4.1: (#{e.inspect}). Failed to convert data types. The event has been discarded. Original data: #{datahash}")
      else
        @logger.warn("PB3 encoder err 2.4.2: (#{e.inspect}). The event has been discarded.")
      end
      nil
    rescue => e
      puts "PB3 encoder error 2.5: (#{e.inspect}). Original data: #{datahash} #{e.backtrace}" # TODO remove
      @logger.warn("PB3 encoder err 2.5: (#{e.inspect}). The event has been discarded. Auto-typecasting was on: #{@pb3_encoder_autoconvert_types}. Original data: #{datahash}")
      nil
    end
  end # pb3_handle_type_errors

  def pb3_get_type_mismatches(data, key_prefix, pb_class)
    begin
      mismatches = []
      data.to_hash.each do |key, value|
          expected_type = pb3_get_expected_type(key, pb_class)
          r = pb3_compare_datatypes(value, key, key_prefix, pb_class, expected_type)
          mismatches.concat(r)
      end # data.each
      mismatches
    rescue => e
      @logger.warn("PB3 encoder err 11: (#{e.inspect}). Key: #{key}, class: #{pb_class}")
    end
  end

  def pb3_get_expected_type(key, pb_class)
    pb_descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_class)
    if !pb_descriptor.nil?
      pb_builder = pb_descriptor.msgclass
      pb_obj = pb_builder.new({})
      begin
        v = pb_obj.send(key)
        if !v.nil?
          v.class
        else
          nil
        end
      rescue => e
        # This can happen when a fieldname is a reserved word, such as :method
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
        if descriptor.nil?
          puts "Could not find descriptor for key #{key}, prefix #{key_prefix} in class #{pb_class}"
          return []
        end
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
                @logger.debug("PB3 encoder err 5: Could not convert types for protobuf encoding: #{ex}")
            end
        end # if key contains .
    end # mismatches.each
    struct
  end

  def pb3_prepare_for_encoding(datahash, pb_class, parent_fields)
    puts "pb3_prepare_for_encoding #{pb_class} #{parent_fields} #{datahash}"
    # TODO parent_fields might be removed

    # 0) Remove empty fields.
    datahash = datahash.select { |key, value| !value.nil? }

    # Preparation: the data cannot be encoded until certain criteria are met:
    # 1) remove @ signs from keys.
    # 2) convert timestamps and other objects to strings
    datahash = datahash.inject({}){|x,(k,v)| x[k.gsub(/@/,'').to_sym] = (should_convert_to_string?(v) ? v.to_s : v); x}

    if @pb3_encoder_drop_unknown_fields
      datahash = datahash.select { |k, v| pb3_field_defined(k, pb_class) }
    end

    datahash.each do |key, val|
      if val.is_a?(Hash)
        new_parents = parent_fields.clone().append(key)
        field_pb_class = @metainfo_messageclasses[pb_class][key.to_s]
        datahash[key] = pb3_prepare_for_encoding(val, field_pb_class, new_parents)
      end

      if val.is_a?(Array)
        puts "array found #{key} of size #{val.length}\n#{val}" # TODO remove
        new_list = []
        val.each { |v|
          if v.is_a?(Hash)
            puts "imma hash"
            field_pb_class = @metainfo_messageclasses[pb_class][key.to_s]
            puts "my class is #{field_pb_class}"
            v2 = pb3_prepare_for_encoding(v, field_pb_class, parent_fields)
            puts "success v2"
            new_list << v2
          else
            new_list << v
          end

        }

        datahash[key] = new_list
      end # val is array
    end # datahash.each
    datahash
  rescue => e
    @logger.warn("PB3 encoder err 10: #{e}. Data: #{datahash}. Parent class: #{pb_class}. #{e.backtrace}")
    datahash
  end


  def pb3_field_defined(field_name, pb_class)
    begin
      if @metainfo_existingfields.key? pb_class
        field_exists = @metainfo_existingfields[pb_class].include?(field_name.to_s)
        puts "Field #{field_name} exists in class #{pb_class} => #{field_exists}"
        if ! field_exists
          puts @metainfo_existingfields
        end
        field_exists
      else
         @logger.warn("PB3 encoder err 3.1: meta info not found for field: #{field_name} of class: #{pb_class} in #{@metainfo_existingfields}")
      true # when in doubt assume that the field is there
      end
    rescue => e
      @logger.warn("PB3 encoder err 3.2: #{e}. Key: #{field_name}. Parent class: #{pb_class}. #{@metainfo_existingfields}")
      true # when in doubt assume that the field is there
    end
  end


  def pb3_get_oneof_metainfo(pb_object, pb_class_name)
    meta = {}
    pb_class = Google::Protobuf::DescriptorPool.generated_pool.lookup(pb_class_name).msgclass

    pb_class.descriptor.each_oneof { |field|
      field.each { | group_option |
        if !pb_object.send(group_option.name).nil?
            meta[field.name] = group_option.name
        end
      }
    }

    pb_class.descriptor.select{ |field| field.type == :message }.each { | field |
      # recurse over nested protobuf classes
      pb_sub_object = pb_object.send(field.name)
      if !pb_sub_object.nil? and !field.subtype.nil?
          pb_sub_class = pb3_get_descriptorpool_name(field.subtype.msgclass)
          meta[field.name] = pb3_get_oneof_metainfo(pb_sub_object, pb_sub_class)
      end
    }

    meta
  end


  def pb2_encode(event)
    data = pb2_prepare_for_encoding(event.to_hash, @class_name)
    msg = @pb_builder.new(data)
    msg.serialize_to_string
  rescue NoMethodError => e
    @logger.warn("PB2 encoder err 1. Probably mismatching protobuf definition. Required fields in the protobuf definition are: " + event.to_hash.keys.join(", ") + " and the timestamp field name must not include a @. ")
    raise e
  rescue => e
    @logger.warn("PB2 encoder err 2: #{e.inspect}")
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
                proto_obj.new(pb2_prepare_for_encoding(original_value, c)) # this line is reached in the colourtest for an enum. Enums should not be instantiated. Should enums even be in the messageclasses? I dont think so! TODO bug
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
    regex_require = /\s*require \'(?<require_file>.+?)\'\s*/ # TODO optimize both regexes for speed (negative lookahead)
    regex_class_name = /\s*add_message "(?<name>.+?)" do\s+/
    regex_pbdefs = /\s*(optional|repeated)(\s*):(?<name>.+),(\s*):(?<type>\w+),(\s*)(?<position>\d+)(, \"(?<enum_class>.*?)\")?/
    class_name = ""
    type = ""
    field_name = ""
    includes = []
    File.readlines(filename).each do |line|
      if ! (line =~ regex_require).nil?
        required = $1
        unless required == "google/protobuf"
          includes << required
        end
      end # if
      if ! (line =~ regex_class_name).nil?
        class_name = $1
        @metainfo_messageclasses[class_name] = {}
        @metainfo_enumclasses[class_name] = {}
      end # if
      if ! (line =~ regex_pbdefs).nil?
        field_name = $1
        type = $2
        field_class_name = $4

        if !@metainfo_existingfields.key? class_name
          @metainfo_existingfields[class_name] = []
        end
        @metainfo_existingfields[class_name] << field_name

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

    includes.each do |f|
      pb3_metadata_analyis "#{@protobuf_root_directory}/#{f}.rb"
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
      @logger.warn("Error 7: class name not found in file  " + filename)
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
    else
      @logger.warn("Not a ruby file: " + filename)
    end
  end

end # class LogStash::Codecs::Protobuf
