# Logstash protobuf codec

This is a codec plugin for [Logstash](https://github.com/elastic/logstash) to parse protobuf messages.

# Prerequisites and Installation

* prepare your Ruby versions of the Protobuf definitions:
  * For protobuf 2 use the [ruby-protoc compiler](https://github.com/codekitchen/ruby-protocol-buffers).
  * For protobuf 3 use the [official google protobuf compiler](https://developers.google.com/protocol-buffers/docs/reference/ruby-generated).
* install the codec: `bin/logstash-plugin install logstash-codec-protobuf`
* use the codec in your Logstash config file. See details below.

Note: the latest supported jruby version of Google's protobuf library is 3.5.0.pre. If you need to use a more current version, please find instructions [here](google-protobuf-lib-update.md).

## Configuration

There are two ways to specify the locations of the ruby protobuf definitions:
* specify each class and their loading order using the configurations `include_path`. This option will soon be deprecated in favour of the autoloader.
* specify the path to the main protobuf class, and a folder from which to load its dependencies, using `class_file`  and `protobuf_root_directory`. The codec will detect the dependencies of each file and load them automatically.

`include_path`  (optional): an array of strings with filenames where logstash can find your protobuf definitions. Requires absolute paths. Please note that protobuf v2 files have the ending `.pb.rb` whereas files compiled for protobuf v3 end in `_pb.rb`.  Cannot be used together with `protobuf_root_directory` or `class_file`.

`protobuf_root_directory` (optional): Only to be used in combination with `class_file`. Absolute path to the directory that contains all compiled protobuf files. Cannot be used together with `include_path`.

`class_file`  (optional): Relative path to the ruby file that contains class_name. Only to be used in combination with `protobuf_root_directory`. Cannot be used together with `include_path`.

`class_name`    (required): the name of the protobuf class that is to be decoded or encoded. For protobuf 2 separate the modules with ::. For protobuf 3 use single dots.

`protobuf_version` (optional): set this to 3 if you want to use protobuf 3 definitions. Defaults to 2.

`stop_on_error` (optional): Decoder only: will stop the entire pipeline upon discovery of a non decodable message. Deactivated by default.

`pb3_encoder_autoconvert_types` (optional): Encoder only: will try to fix type mismatches between the protobuf definition and the actual data. Available for protobuf 3 only. Activated by default.

## Usage example: decoder

Use this as a codec in any logstash input. Just provide the name of the class that your incoming objects will be encoded in, and specify the path to the compiled definition.
Here's an example for a kafka input with protobuf 2:

```ruby
kafka
{
  topic_id => "..."
  key_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
  value_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"

  codec => protobuf
  {
    class_name => "Animals::Mammals::Unicorn"
    include_path => ['/path/to/pb_definitions/Animal.pb.rb', '/path/to/pb_definitions/Unicorn.pb.rb']
  }
}
```

Example for protobuf 3, manual class loading specification (deprecated):

```ruby
kafka
{
  topic_id => "..."
  key_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
  value_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
  codec => protobuf
  {
    class_name => "Animals.Mammals.Unicorn"
    include_path => ['/path/to/pb_definitions/Animal_pb.rb', '/path/to/pb_definitions/Unicorn_pb.rb']
    protobuf_version => 3
  }
}
```

Example for protobuf 3, automatic class loading specification:

```ruby
kafka
{
  topic_id => "..."
  key_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
  value_deserializer_class => "org.apache.kafka.common.serialization.ByteArrayDeserializer"
  codec => protobuf
  {
    class_name => "Animals.Mammals.Unicorn"
    class_file => '/path/to/pb_definitions/some_folder/Unicorn_pb.rb'
    protobuf_root_directory => "/path/to/pb_definitions/"
    protobuf_version => 3
  }
}
```
In this example, all protobuf files must live in a subfolder of `/path/to/pb_definitions/`.

For version 3 class names check the bottom of the generated protobuf ruby file. It contains lines like this:

```ruby
Animals.Unicorn = Google::Protobuf::DescriptorPool.generated_pool.lookup("Animals.Unicorn").msgclass
```

Use the parameter for the lookup call as the class_name for the codec config.

If you're using a kafka input please also set the deserializer classes as shown above.

### Class loading order

Imagine you have the following protobuf version 2 relationship: class Unicorn lives in namespace Animal::Horse and uses another class Wings.

```ruby
module Animal
  module Mammal
    class Unicorn
      set_fully_qualified_name "Animal.Mammal.Unicorn"
      optional ::Bodypart::Wings, :wings, 1
      optional :string, :name, 2
      ...
```

Make sure to put the referenced wings class first in the include_path:

```ruby
include_path => ['/path/to/pb_definitions/wings.pb.rb','/path/to/pb_definitions/unicorn.pb.rb']
```

Set the class name to the parent class:

```ruby
class_name => "Animal::Mammal::Unicorn"
```

for protobuf 2. For protobuf 3 use

```ruby
class_name => "Animal.Mammal.Unicorn"
```

## Usage example: encoder

The configuration of the codec for encoding logstash events for a protobuf output is pretty much the same as for the decoder input usage as demonstrated above, with the following exception: when writing to the Kafka output,
* do not set the `value_deserializer_class` or the `key_deserializer_class`.
* do set the serializer class like so: `value_serializer => "org.apache.kafka.common.serialization.ByteArraySerializer"`.

Please be aware of the following:
* the protobuf definition needs to contain all the fields that logstash typically adds to an event, in the corrent data type. Examples for this are `@timestamp` (string), `@version` (string), `host`, `path`, all of which depend on your input sources and filters aswell. If you do not want to add those fields to your protobuf definition then please use a [modify filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html) to [remove](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html#plugins-filters-mutate-remove_field) the undesired fields.
* object members starting with `@` are somewhat problematic in protobuf definitions. Therefore those fields will automatically be renamed to remove the at character. This also effects the important `@timestamp` field. Please name it just "timestamp" in your definition.
* fields with a nil value will automatically be removed from the event. Empty fields will not be removed.
* it is recommended to set the config option `pb3_encoder_autoconvert_types` to true. Otherwise any type mismatch between your data and the protobuf definition will cause an event to be lost. The auto typeconversion does not alter your data. It just tries to convert obviously identical data into the expected datatype, such as converting integers to floats where floats are expected, or "true" / "false" strings into booleans where booleans are expected.

```ruby
  kafka
    {
      codec => protobuf
      {
        class_name => "Animals.Mammals.Unicorn"
        class_file => '/path/to/pb_definitions/some_folder/Unicorn_pb.rb'
        protobuf_root_directory => "/path/to/pb_definitions/"
        protobuf_version => 3
      }
      ...
      value_serializer => "org.apache.kafka.common.serialization.ByteArraySerializer"
    }
  }
```

## Troubleshooting

### Decoder: Protobuf 2
#### "uninitialized constant SOME_CLASS_NAME"

If you include more than one definition class, consider the order of inclusion. This is especially relevant if you include whole directories. A definition might refer to another definition that is not loaded yet. In this case, please specify the files in the `include_path` variable in reverse order of reference. See 'Example with referenced definitions' above.

#### no protobuf output

Maybe your protobuf definition does not fullfill the requirements and needs additional fields. Run logstash with the `--debug` flag and search for error messages.

### Decoder: Protobuf 3

#### NullPointerException

Check for missing imports. There's a high probability that one of the imported classes has dependencies of its own and those are not being fully satisfied. To avoid this, consider using the autoloader feature by setting the configurations for `protobuf_root_directory` and `class_file`.

### Encoder: Protobuf 3

#### NullPointerException

Check for missing imports. There's a high probability that one of the imported classes has dependencies of its own and those are not being fully satisfied. To avoid this, consider using the autoloader feature by setting the configurations for `protobuf_root_directory` and `class_file`.


