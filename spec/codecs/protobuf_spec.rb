require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers
require "insist"

describe LogStash::Codecs::Protobuf do

  context "#decode" do

    let(:plugin) { LogStash::Codecs::Protobuf.new("class_name" => "Animal::Unicorn", "include_path" => ['spec/helpers/unicorn.pb.rb'])  }
    before do
        plugin.register
    end

    it "should return an event from protobuf encoded data" do
    
      data = {:colour => 'rainbow', :horn_length => 18, :last_seen => 1420081471}
      unicorn = Animal::Unicorn.new(data)
        
      plugin.decode(unicorn.serialize_to_string) do |event|

        expect(event["colour"] ).to eq(data[:colour] )
        expect(event["horn_length"] ).to eq(data[:horn_length] )
        expect(event["last_seen"] ).to eq(data[:last_seen] )
      end
    end
  end


  context "#encode" do

    let(:plugin) { LogStash::Codecs::Protobuf.new("class_name" => "Animal::Unicorn", "include_path" => ['spec/helpers/unicorn.pb.rb'])  }
    before do
        plugin.register
    end

    it "should return protobuf encoded data from an event" do
      event_fields = {"colour" => 'rainbow', "horn_length" => 18, "last_seen" => 1420081471}
      event = LogStash::Event.new(event_fields)        
      plugin.encode(event) do |output|
        
        unicorn = Animal::Unicorn.new(output)
        expect(unicorn["colour"] ).to eq(event_fields["colour"] )
        expect(unicorn["horn_length"] ).to eq(event_fields["horn_length"] )
        expect(unicorn["last_seen"] ).to eq(event_fields["last_seen"] )
      end
    end
  end
end
