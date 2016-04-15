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
    
      data = {:colour => 'rainbow', :horn_length => 18, :last_seen => 1420081471, :has_wings => true}
      unicorn = Animal::Unicorn.new(data)
        
      plugin.decode(unicorn.serialize_to_string) do |event|

        expect(event["colour"] ).to eq(data[:colour] )
        expect(event["horn_length"] ).to eq(data[:horn_length] )
        expect(event["last_seen"] ).to eq(data[:last_seen] )
        expect(event["has_wings"] ).to eq(data[:has_wings] )
      end
    end
  end

  # TODO add test case: #encode with more complex protobuf object which has arrays and nested protobuf objects. We need to test the recursion of the encoder after it is implemented

  context "#encode" do
=begin
    let(:plugin) { LogStash::Codecs::Protobuf.new("class_name" => "Animal::UnicornEvent", "include_path" => ['spec/helpers/unicorn_event.pb.rb'])  }
    before do
        plugin.register  
    
    end

    it "should return protobuf encoded data from an event" do
      event_fields = {"colour" => 'pink', "horn_length" => 12, "last_seen" => 1410081999}
      event = LogStash::Event.new(event_fields)        
      plugin.encode(event) do |output|  # TODO for some reason this is not working when called from the rspec
        
        unicorn = Animal::UnicornEvent.new(output)
        expect(unicorn["colour"] ).to eq(event_fields["colour"] )
        expect(unicorn["horn_length"] ).to eq(event_fields["horn_length"] )
        expect(unicorn["last_seen"] ).to eq(event_fields["last_seen"] )
        # todo check that timestamps is set
        # todo check that timestamps is set
      end
    end # it
=end
    #-----------

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Animal::UnicornEvent", "include_path" => ['spec/helpers/unicorn_event.pb.rb']) 
    end

    #event_fields = {"colour" => 'pink', "horn_length" => 12, "last_seen" => 1410081999} # TODO remove
    event = LogStash::Event.new("colour" => "pink", "horn_length" => 12, "last_seen" => 1410081999, "has_wings" => true)    

    it "should return protobuf encoded data from an event" do
      subject.on_event do |event, data|
        insist { data.is_a? String }
        puts "Protobytes: " + data.to_s # TODO remove
        unicorn = Animal::UnicornEvent.parse(data) # FAIL todo
        puts "unicorn: " + unicorn.inspect.to_s # TODO remove
        expect(unicorn.colour ).to eq(event["colour"] )
        expect(unicorn.horn_length ).to eq(event["horn_length"] )
        expect(unicorn.last_seen ).to eq(event["last_seen"] )
        expect(unicorn.has_wings ).to eq(event["has_wings"] )
        #insist { data } == "foo.bar.#{name}.baz #{value} #{timestamp.to_i}\n"
      end
      subject.encode(event)
    end


  end # context
end
