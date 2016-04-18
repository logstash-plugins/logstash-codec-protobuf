# Logstash protobuf codec

This is a codec plugin for [Logstash](https://github.com/elastic/logstash) to parse protobuf messages.

# Prerequisites and Installation
 
* prepare your ruby versions of the protobuf definitions, for example using the ruby-protoc compiler from https://github.com/codekitchen/ruby-protocol-buffers
* download the [gem file](https://rubygems.org/gems/logstash-codec-protobuf) to your computer.
* Install the plugin. From within your logstash directory, do
	bin/plugin install /path/to/logstash-codec-protobuf-$VERSION.gem
* use the codec in your logstash config file. See details below.

## Configuration

include_path  (required): an array of strings with filenames or directory names where logstash can find your protobuf definitions. Please provide absolute paths. For directories it will only try to import files ending on .rb

class_name    (required): the name of the protobuf class that is to be decoded or encoded.

## Usage example: decoder

Use this as a codec in any logstash input. Just provide the name of the class that your incoming objects will be encoded in, and specify the path to the compiled definition.
Here's an example for a kafka input:

	kafka 
  	{
      zk_connect => "127.0.0.1"
      topic_id => "unicorns_protobuffed"
      codec => protobuf 
      {
        class_name => "Unicorn"
        include_path => ['/my/path/to/compiled/protobuf/definitions/UnicornProtobuf.pb.rb']
      }
  	}   

### Example with referenced definitions

Imagine you have the following protobuf relationship: class Cheese lives in namespace Foods::Dairy and uses another class Milk. 

	module Foods
  		module Dairy
    		class Cheese
    			set_fully_qualified_name "Foods.Dairy.Cheese"
			    optional ::Foods::Cheese::Milk, :milk, 1
			    optional :int64, :unique_id, 2
			    # here be more field definitions

Make sure to put the referenced Milk class first in the include_path:

	include_path => ['/path/to/protobuf/definitions/Milk.pb.rb','/path/to/protobuf/definitions/Cheese.pb.rb']

Set the class name to the parent class:
	
	class_name => "Foods::Dairy::Cheese"

## Usage example: encoder

The configuration of the codec for encoding logstash events for a protobuf output is pretty much the same as for the decoder input usage as demonstrated above. There are some constraints though that you need to be aware of:
* the protobuf definition needs to contain all the fields that logstash typically adds to an event, in the corrent data type. Examples for this are @timestamp (string), @version (string), host, path, all of which depend on your input sources and filters aswell. If you do not want to add those fields to your protobuf definition then please use a [modify filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html) to [remove](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html#plugins-filters-mutate-remove_field) the undesired fields.
* object members starting with @ are somewhat problematic in protobuf definitions. Therefore those fields will automatically be renamed to remove the at character. This also effects the important @timestamp field. Please name it just "timestamp" in your definition.


## Troubleshooting

### "uninitialized constant SOME_CLASS_NAME"

If you include more than one definition class, consider the order of inclusion. This is especially relevant if you include whole directories. A definition might refer to another definition that is not loaded yet. In this case, please specify the files in the include_path variable in reverse order of reference. See 'Example with referenced definitions' above.

### no protobuf output

Maybe your protobuf definition does not fullfill the requirements and needs additional fields. Run logstash with the --debug flag and grep for "error 2".


## Limitations and roadmap

* maybe add support for setting undefined fields from default values in the decoder

