# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"
require "insist"


require 'google/protobuf' # for protobuf3


describe LogStash::Codecs::Protobuf do


  context "#decodePB3" do


    #### Test case 1: Decode simple protobuf ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => ['spec/helpers/pb3/unicorn_pb.rb'], "protobuf_version_3" => true)  }
    before do
        plugin_unicorn.register      
    end

    it "should return an event from protobuf encoded data" do
    
      unicorn_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass
      data = {:name => 'Pinkie', :age => 18, :is_pegasus => false, :favourite_numbers => [4711,23], :fur_colour => Colour::PINK, 
      :favourite_colours => [Colour::GREEN, Colour::BLUE]
      }
      
      unicorn_object = unicorn_class.new(data)
      bin = unicorn_class.encode(unicorn_object)
      plugin_unicorn.decode(bin) do |event|
        expect(event.get("name") ).to eq(data[:name] )
        expect(event.get("age") ).to eq(data[:age])
        expect(event.get("fur_colour") ).to eq("PINK")
        expect(event.get("favourite_numbers") ).to eq(data[:favourite_numbers])
        expect(event.get("favourite_colours") ).to eq(["GREEN","BLUE"])
        expect(event.get("is_pegasus") ).to eq(data[:is_pegasus] )
      end
    end # it





    #### Test case 2: Decode ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => ['spec/helpers/pb3/unicorn_pb.rb'], "protobuf_version_3" => true)  }
    before do
        plugin_unicorn.register      
    end

    it "should return an event from protobuf encoded data" do
    
      unicorn_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass
      data = {:name => 'Glitter', :fur_colour => Colour::GLITTER
      }
      
      unicorn_object = unicorn_class.new(data)
      bin = unicorn_class.encode(unicorn_object)
      plugin_unicorn.decode(bin) do |event|
        expect(event.get("name") ).to eq(data[:name] )
        expect(event.get("fur_colour") ).to eq("GLITTER" )

      end
    end # it


  end # context #decodePB3

  # TODO encodePB3

 



end # describe
