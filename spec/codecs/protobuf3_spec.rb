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





    #### Test case 2: decode nested protobuf ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => ['spec/helpers/pb3/unicorn_pb.rb'], "protobuf_version_3" => true)  }
    before do
        plugin_unicorn.register      
    end

    it "should return an event from protobuf encoded data with nested classes" do
    

      unicorn_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass

      father = unicorn_class.new({:name=> "Sparkle", :age => 50, :fur_colour => 3 })
      data = {:name => 'Glitter', :fur_colour => Colour::GLITTER, :father => father}   
     
      unicorn_object = unicorn_class.new(data)
      bin = unicorn_class.encode(unicorn_object)
      plugin_unicorn.decode(bin) do |event|
        expect(event.get("name") ).to eq(data[:name] )
        expect(event.get("fur_colour") ).to eq("GLITTER" )
        expect(event.get("father")["name"] ).to eq(data[:father][:name] )
        expect(event.get("father")["age"] ).to eq(data[:father][:age] )
        expect(event.get("father")["fur_colour"] ).to eq("SILVER")

      end
    end # it



    #### Test case 3: decode ProbeResult ####################################################################################################################
    let(:plugin_3) { LogStash::Codecs::Protobuf.new("class_name" => "ProbeResult", "include_path" => ['spec/helpers/pb3/ProbeResult_pb.rb'], "protobuf_version_3" => true)  }
    before do
        plugin_3.register      
    end

    it "should return an event from protobuf encoded data with nested classes" do
    

      probe_result_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("ProbeResult").msgclass
      ping_result_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("PingIPv4Result").msgclass

      ping_result_data = {:status=> PingIPv4Result::Status::ERROR, 
        :latency => 50, :ip => "8.8.8.8", :probe_ip => "127.0.0.1", :geolocation => "New York City" }
      ping_result_object = ping_result_class.new(ping_result_data)

      probe_result_data = {:UUID => '12345678901233456789', :TaskPingIPv4Result => ping_result_object}   
      probe_result_object = probe_result_class.new(probe_result_data)
      bin = probe_result_class.encode(probe_result_object)
      plugin_3.decode(bin) do |event|
        expect(event.get("UUID") ).to eq(probe_result_data[:UUID] )
        expect(event.get("TaskPingIPv4Result")["status"] ).to eq("ERROR")
        expect(event.get("TaskPingIPv4Result")["latency"] ).to eq(ping_result_data[:latency] )
        expect(event.get("TaskPingIPv4Result")["ip"] ).to eq(ping_result_data[:ip] )
        expect(event.get("TaskPingIPv4Result")["probe_ip"] ).to eq(ping_result_data[:probe_ip] )
        expect(event.get("TaskPingIPv4Result")["geolocation"] ).to eq(ping_result_data[:geolocation] )
      end
    end # it


  end # context #decodePB3


  context "#encodePB3-a" do

    #### Test case 3: encode simple protobuf ####################################################################################################################

    definitions_file = 'spec/helpers/pb3/unicorn_pb.rb'
    require definitions_file

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => [definitions_file], "protobuf_version_3" => true)
    end

    event3 = LogStash::Event.new("name" => "Pinkie", "age" => 18, "is_pegasus" => false, "favourite_numbers" => [1,2,3], "fur_colour" => Colour::PINK, "favourite_colours" => [1,5]      )

    it "should return protobuf encoded data for testcase 3" do

      subject.on_event do |event, data|
        insist { data.is_a? String }

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass
        decoded_data = pb_builder.decode(data) 
        expect(decoded_data.name ).to eq(event.get("name") )
        expect(decoded_data.age ).to eq(event.get("age") )
        expect(decoded_data.is_pegasus ).to eq(event.get("is_pegasus") )
        expect(decoded_data.fur_colour ).to eq(:PINK)
        expect(decoded_data.favourite_numbers ).to eq(event.get("favourite_numbers") )
        expect(decoded_data.favourite_colours ).to eq([:BLUE,:WHITE] )
      end # subject.on_event
      subject.encode(event3)
    end # it

  end # context

  context "#encodePB3-b" do

    #### Test case 4: encode nested protobuf ####################################################################################################################

    definitions_file = 'spec/helpers/pb3/unicorn_pb.rb'
    require definitions_file

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => [definitions_file], "protobuf_version_3" => true)
    end

    event4 = LogStash::Event.new("name" => "Horst", "age" => 23, "is_pegasus" => true, "mother" => \
        {"name" => "Mom", "age" => 47}, "father" => {"name"=> "Daddy", "age"=> 50, "fur_colour" => 3 } # 3 == SILVER      
      )

    it "should return protobuf encoded data for testcase 4" do

      subject.on_event do |event, data|
        insist { data.is_a? String }

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass
        decoded_data = pb_builder.decode(data) 
        
        expect(decoded_data.name ).to eq(event.get("name") )
        expect(decoded_data.age ).to eq(event.get("age") )
        expect(decoded_data.is_pegasus ).to eq(event.get("is_pegasus") )
        expect(decoded_data.mother.name ).to eq(event.get("mother")["name"] )
        expect(decoded_data.mother.age ).to eq(event.get("mother")["age"] )
        expect(decoded_data.father.name ).to eq(event.get("father")["name"] )
        expect(decoded_data.father.age ).to eq(event.get("father")["age"] )
        expect(decoded_data.father.fur_colour ).to eq(:SILVER)

      
      end # subject4.on_event
      subject.encode(event4)
    end # it

  end # context #encodePB3

end # describe
