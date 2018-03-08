# Logstash protobuf codec

This is a codec plugin for [Logstash](https://github.com/elastic/logstash) to parse protobuf messages.

# Prerequisites and Installation
 
* prepare your ruby versions of the protobuf definitions
** For protobuf 2 use the [ruby-protoc compiler](https://github.com/codekitchen/ruby-protocol-buffers).
** For protobuf 3 use the [official google protobuf compiler](https://developers.google.com/protocol-buffers/docs/reference/ruby-generated).
* install the codec: `bin/logstash-plugin install logstash-codec-protobuf`
* use the codec in your logstash config file. See details below.

## Configuration

include_path  (required): an array of strings with filenames where logstash can find your protobuf definitions. Please provide absolute paths. For directories it will only try to import files ending on .rb

class_name    (required): the name of the protobuf class that is to be decoded or encoded. For protobuf 2 separate the modules with ::. For protobuf 3 use single dots. See examples below.

protobuf_version_3 (optional): set this to true if you want to use protobuf 3 definitions. 

## Usage example: decoder

Use this as a codec in any logstash input. Just provide the name of the class that your incoming objects will be encoded in, and specify the path to the compiled definition.
Here's an example for a kafka input with protobuf 2:

	kafka 
	{
	  zk_connect => "127.0.0.1"
	  topic_id => "unicorns_protobuffed"
	  codec => protobuf 
	  {
	    class_name => "Animals::Unicorn"
	    include_path => ['/path/to/protobuf/definitions/Animal.pb.rb', '/path/to/protobuf/definitions/UnicornProtobuf.pb.rb']
	  }
	}

Example for protobuf 3:

	kafka 
	{
	  zk_connect => "127.0.0.1"
	  topic_id => "unicorns_protobuffed"
	  codec => protobuf 
	  {
      class_name => "Animals.Unicorn"
	    include_path => ['/path/to/protobuf/definitions/Animal_pb.rb', '/path/to/protobuf/definitions/UnicornProtobuf_pb.rb']
	    protobuf_version_3 => true
	  }
	}	 

### Class loading order

Imagine you have the following protobuf version 2 relationship: class Unicorn lives in namespace Animal::Horse and uses another class Wings. 

	module Animal
	  module Horse
	    class Unicorn
	      set_fully_qualified_name "Animal.Horse.Unicorn"
	      optional ::Animal::Bodypart::Wings, :wings, 1
	      optional :string, :name, 2
	      # here be more field definitions

Make sure to put the referenced wings class first in the include_path:

	include_path => ['/path/to/protobuf/definitions/wings.pb.rb','/path/to/protobuf/definitions/unicorn.pb.rb']

Set the class name to the parent class:
	
	class_name => "Animal::Horse::Unicorn"

for protobuf 2. For protobuf 3 use 

	class_name => "Animal.Horse.Unicorn"


## Usage example: encoder

The configuration of the codec for encoding logstash events for a protobuf output is pretty much the same as for the decoder input usage as demonstrated above. There are some constraints though that you need to be aware of:
* the protobuf definition needs to contain all the fields that logstash typically adds to an event, in the corrent data type. Examples for this are @timestamp (string), @version (string), host, path, all of which depend on your input sources and filters aswell. If you do not want to add those fields to your protobuf definition then please use a [modify filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html) to [remove](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html#plugins-filters-mutate-remove_field) the undesired fields.
* object members starting with @ are somewhat problematic in protobuf definitions. Therefore those fields will automatically be renamed to remove the at character. This also effects the important @timestamp field. Please name it just "timestamp" in your definition.


## Troubleshooting

### Protobuf 2 
#### "uninitialized constant SOME_CLASS_NAME"

If you include more than one definition class, consider the order of inclusion. This is especially relevant if you include whole directories. A definition might refer to another definition that is not loaded yet. In this case, please specify the files in the include_path variable in reverse order of reference. See 'Example with referenced definitions' above.

#### no protobuf output

Maybe your protobuf definition does not fullfill the requirements and needs additional fields. Run logstash with the --debug flag and search for error messages.

### Protobuf 3

Tba.

## Limitations and roadmap

* maybe add support for setting undefined fields from default values in the decoder


