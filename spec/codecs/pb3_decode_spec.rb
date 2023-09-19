# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"

require 'google/protobuf' # for protobuf3

# absolute path to the protobuf helpers directory
pb_include_path = File.expand_path(".") + "/spec/helpers"

# Include the protobuf definitions so that we can reference the classes
# directly instead of looking them up in the pb decriptor pool
['./pb3/header/*.rb', './pb3/*.rb'].each do | d |
  Dir.glob(pb_include_path + d).each do |file|
    require file
  end
end

describe LogStash::Codecs::Protobuf do

  context ".reloadable?" do
    subject do
      next LogStash::Codecs::Protobuf.new(
        "class_name" => "Unicorn",
        "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'],
        "protobuf_version" => 3
      )
    end

    it "returns false" do
      expect(subject.reloadable?).to be_falsey
    end
  end

  ##################################################

  context "config" do
    context "using class_file and include_path" do
      let(:plugin) {
        LogStash::Codecs::Protobuf.new(
          "class_name" => "Unicorn",
          "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'],
          "class_file" => pb_include_path + '/pb3/unicorn_pb.rb',
          "protobuf_version" => 3
        )
      }

      it "should fail to register the plugin with ConfigurationError" do
        expect {plugin.register}.to raise_error(LogStash::ConfigurationError, /`include_path` and `class_file`/)
      end # it
    end

    context "not using class_file or include_path" do
      let(:plugin) {
        LogStash::Codecs::Protobuf.new("class_name" => "Unicorn")
      }

      it "should fail to register the plugin with ConfigurationError" do
        expect {plugin.register}.to raise_error(LogStash::ConfigurationError, /`include_path` or `class_file`/)
      end # it
    end

    RSpec::Expectations.configuration.on_potential_false_positives = :nothing

    context "re-registering the plugin with a valid configuration" do
      let(:plugin) { LogStash::Codecs::Protobuf.new(
        "class_name" => "A.MessageA",
        "class_file" => [ pb_include_path + '/pb3/messageA_pb.rb' ],
        "protobuf_version" => 3,
        "protobuf_root_directory" => File.expand_path(File.dirname(__FILE__) + pb_include_path + '/pb3/'))
      }

      it "should not fail" do
        expect {
          # this triggers the `register()` method of the plugin multiple times
          plugin.register
          plugin.register
        }.not_to raise_error(RuntimeError)
      end # it
    end

  end # context config

  ##################################################

  context "#pb3decoder_test1" do

    # Test case 1: Decode simple protobuf
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new(
      "class_name" => "Unicorn", "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)
    }

    it "should return an event from protobuf data" do

      data = {:name => 'Pinkie', :age => 18, :is_pegasus => false, :favourite_numbers => [4711,23],
        :fur_colour => Colour::PINK, :favourite_colours => [Colour::GREEN, Colour::BLUE]
      }

      unicorn_object = Unicorn.new(data)
      bin = Unicorn.encode(unicorn_object)
      plugin_unicorn.decode(bin) do |event|
        expect(event.get("name")).to eq(data[:name] )
        expect(event.get("age")).to eq(data[:age])
        expect(event.get("fur_colour")).to eq("PINK")
        expect(event.get("favourite_numbers")).to eq(data[:favourite_numbers])
        expect(event.get("favourite_colours")).to eq(["GREEN","BLUE"])
        expect(event.get("is_pegasus")).to eq(data[:is_pegasus] )
      end
    end # it
  end # context

  ##################################################

  context "#pb3decoder_test2" do

    # Test case 2: decode nested protobuf
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn",
     "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)  }

    it "should return an event from protobuf data with nested classes" do
      father = Unicorn.new({:name=> "Sparkle", :age => 50, :fur_colour => 3 })
      data = {:name => 'Glitter', :fur_colour => Colour::GLITTER, :father => father}

      unicorn_object = Unicorn.new(data)
      bin = Unicorn.encode(unicorn_object)
      plugin_unicorn.decode(bin) do |event|
        expect(event.get("name")).to eq(data[:name] )
        expect(event.get("fur_colour")).to eq("GLITTER" )
        expect(event.get("father")["name"]).to eq(data[:father][:name] )
        expect(event.get("father")["age"]).to eq(data[:father][:age] )
        expect(event.get("father")["fur_colour"]).to eq("SILVER")

      end
    end # it

  end # context

  ##################################################

  context "#pb3decoder_test3" do

    # Test case 3: decode ProbeResult
    let(:plugin_3) { LogStash::Codecs::Protobuf.new("class_name" => "ProbeResult",
     "include_path" => [pb_include_path + '/pb3/ProbeResult_pb.rb'], "protobuf_version" => 3)  }

    before do
        plugin_3.register
    end

    it "should return an event from protobuf data with nested classes" do
      ping_result_data = {:status=> PingIPv4Result::Status::ERROR,
        :latency => 50, :ip => "8.8.8.8", :probe_ip => "127.0.0.1", :geolocation => "New York City" }
      ping_result_object = PingIPv4Result.new(ping_result_data)

      probe_result_data = {:UUID => '12345678901233456789', :TaskPingIPv4Result => ping_result_object}
      probe_result_object = ProbeResult.new(probe_result_data)
      bin = ProbeResult.encode(probe_result_object)
      plugin_3.decode(bin) do |event|
        expect(event.get("UUID")).to eq(probe_result_data[:UUID] )
        expect(event.get("TaskPingIPv4Result")["status"]).to eq("ERROR")
        expect(event.get("TaskPingIPv4Result")["latency"]).to eq(ping_result_data[:latency] )
        expect(event.get("TaskPingIPv4Result")["ip"]).to eq(ping_result_data[:ip] )
        expect(event.get("TaskPingIPv4Result")["probe_ip"]).to eq(ping_result_data[:probe_ip] )
        expect(event.get("TaskPingIPv4Result")["geolocation"]).to eq(ping_result_data[:geolocation] )
      end
    end # it
  end # context #pb3decoder_test3

  ##################################################

  context "#pb3decoder_test4" do

    # Test case 4: decode PBDNSMessage
    let(:plugin_4) { LogStash::Codecs::Protobuf.new("class_name" => "PBDNSMessage",
      "include_path" => [pb_include_path + '/pb3/dnsmessage_pb.rb'], "protobuf_version" => 3)  }

    before do
        plugin_4.register
    end

    it "should return an event from protobuf data with nested classes" do
      dns_question_data = {:qName => "Foo", :qType => 12345, :qClass => 67890 }
      dns_question_object = PBDNSMessage::DNSQuestion.new(dns_question_data)

      dns_response_data = {:rcode => 12345, :appliedPolicy => "baz", :tags => ["a","b","c"],
        :queryTimeSec => 123, :queryTimeUsec => 456,
        :appliedPolicyType => PBDNSMessage::PolicyType::NSIP}

      dns_rr_data = [
        {:name => "abc", :type => 9000, :class => 8000, :ttl => 20, :rdata => "300"},
        {:name => "def", :type => 19000, :class => 18000, :ttl => 120, :rdata => "1300"}
      ]

      dns_response_data[:rrs] = dns_rr_data.map { | d | d = PBDNSMessage::DNSResponse::DNSRR.new(d) }
      dns_response_object = PBDNSMessage::DNSResponse.new(dns_response_data)

      pbdns_message_data = {
        # :UUID => '12345678901233456789', :TaskPingIPv4Result => ping_result_object
        :type => PBDNSMessage::Type::DNSIncomingResponseType,
        :messageId => "15",
        :serverIdentity => "16",
        :socketFamily => PBDNSMessage::SocketFamily::INET6,
        :socketProtocol => PBDNSMessage::SocketProtocol::TCP,
        :from => "17",
        :to => "18",
        :inBytes => 70000,
        :timeSec => 80000,
        :timeUsec => 90000,
        :id => 20000,
        :question => dns_question_object,
        :response => dns_response_object,
        :originalRequestorSubnet => "19",
        :requestorId => "Bar",
        :initialRequestId => "20",
        :deviceId => "21",
        }
      pbdns_message_object = PBDNSMessage.new(pbdns_message_data)
      bin = PBDNSMessage.encode(pbdns_message_object)
      plugin_4.decode(bin) do |event|

        ['messageId', 'serverIdentity','from','to','inBytes','timeUsec','timeSec','id', 'originalRequestorSubnet', 'requestorId' ,'initialRequestId','deviceIdf'].each { |n|
          expect(event.get(n)).to eq(pbdns_message_data[n.to_sym] ) }

        # enum test:
        expect(event.get("type")).to eq("DNSIncomingResponseType" )
        expect(event.get("socketFamily")).to eq("INET6" )
        expect(event.get("socketProtocol")).to eq("TCP" )

        expect(event.get("question")["qName"]).to eq(dns_question_data[:qName] )
        expect(event.get("question")["qType"]).to eq(dns_question_data[:qType] )
        expect(event.get("question")["qClass"]).to eq(dns_question_data[:qClass] )

        ['rcode', 'appliedPolicy','tags','queryTimeSec','queryTimeUsec'].each { |n|   expect(event.get('response')[n]).to eq(dns_response_data[n.to_sym] )   }
        expect(event.get("response")['appliedPolicyType']).to eq("NSIP" )

        dns_rr_data.each_with_index { | data, index |
          found = event.get("response")['rrs'][index]
          ['name', 'type','class','ttl','rdata'].each { |n|   expect(found[n]).to eq(data[n.to_sym])   }
        }

      end
    end # it

  end # context pb3decoder_test4

  ##################################################

  context "#pb3decoder_test5" do

    # Test case 5: decode test case for github issue 17
    let(:plugin_5) { LogStash::Codecs::Protobuf.new("class_name" => "com.foo.bar.IntegerTestMessage", "include_path" => [pb_include_path + '/pb3/integertest_pb.rb'], "protobuf_version" => 3)  }

    before do
      plugin_5.register
    end

    it "should return an event from protobuf data with nested classes" do
      integertest_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("com.foo.bar.IntegerTestMessage").msgclass
      integertest_object = integertest_class.new({:response_time => 500})
      bin = integertest_class.encode(integertest_object)
      plugin_5.decode(bin) do |event|
        expect(event.get("response_time")).to eq(500)
      end
    end # it

  end # context pb3decoder_test5

  ##################################################

  context "#pb3decoder_test6" do

    let(:execution_context) { double("execution_context")}
    let(:pipeline_id) {rand(36**8).to_s(36)}

    # Test case 6: decode a message automatically loading the dependencies
    let(:plugin) { LogStash::Codecs::Protobuf.new(
      "class_name" => "A.MessageA",
      "class_file" => [ 'messageA_pb.rb' ],
      "protobuf_version" => 3,
      "protobuf_root_directory" => pb_include_path + '/pb3/')
    }

    before do
      allow(plugin).to receive(:execution_context).and_return(execution_context)
      allow(execution_context).to receive(:pipeline_id).and_return(pipeline_id)

      # this is normally done on the input plugins we "mock" it here to avoid
      # instantiating a dummy input plugin. See
      # https://github.com/ph/logstash/blob/37551a89b8137c1dc6fa4fbd992584c363a36065/logstash-core/lib/logstash/inputs/base.rb#L108
      plugin.execution_context = execution_context
    end

    it "should return an event from protobuf data" do
      header_data = {:name => {'a' => 'b'}}
      header_object = Header.new(header_data)

      message_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("A.MessageA").msgclass
      data = {:name => "Test name", :header => header_object}

      message_object = message_class.new(data)
      bin = message_class.encode(message_object)
      plugin.decode(bin) do |event|
        puts "HELLO RSPEC #{event.inspect} #{event.to_hash}"
        expect(event.get("name")).to eq(data[:name] )
        expect(event.get("header")['name']).to eq(header_data[:name])
      end
    end # it
  end # context

  ##################################################

  context "#pb3decoder_test7" do

    # Test case 6: decode test case for github issue 17
    let(:plugin_7) { LogStash::Codecs::Protobuf.new("class_name" => "RepeatedEvents", 
      "include_path" => [pb_include_path + '/pb3/events_pb.rb'], "protobuf_version" => 3)  }
    before do
        plugin_7.register
    end

    it "should return an event from protobuf data with repeated top level objects" do
      test_a = RepeatedEvent.new({:id => "1", :msg => "a"})
      test_b = RepeatedEvent.new({:id => "2", :msg => "b"})
      test_c = RepeatedEvent.new({:id => "3", :msg => "c"})
      event_obj = RepeatedEvents.new({:repeated_events=>[test_a, test_b, test_c]})
      bin = RepeatedEvents.encode(event_obj)
      plugin_7.decode(bin) do |event|
        expect(event.get("repeated_events").size ).to eq(3)
        expect(event.get("repeated_events")[0]["id"]).to eq("1")
        expect(event.get("repeated_events")[2]["id"]).to eq("3")
        expect(event.get("repeated_events")[0]["msg"]).to eq("a")
        expect(event.get("repeated_events")[2]["msg"]).to eq("c")
      end
    end # it

  end # context pb3decoder_test7

  ##################################################

  context "#pb3decoder_test8a" do

    let(:plugin_8a) { LogStash::Codecs::Protobuf.new("class_name" => "FantasyHorse", "class_file" => 'pb3/FantasyHorse_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)  }
    before do
        plugin_8a.register
    end

    it "should add meta information on oneof fields" do
      pegasus_data = {:wings_length => 100}
      horsey = FantasyPegasus.new(pegasus_data)

      braid_data = {:braid_thickness => 10, :braiding_style => "french"}
      tail_data = {:tail_length => 80, :braided => BraidedHorseTail.new(braid_data) }
      tail = FantasyHorseTail.new(tail_data)

      data = {:name=>"Reinhold", :pegasus => horsey, :tail => tail}
      pb_obj = FantasyHorse.new(data)
      bin = FantasyHorse.encode(pb_obj)
      plugin_8a.decode(bin) do |event|

        expect(event.get("name")).to eq(data[:name])
        expect(event.get("pegasus")["wings_length"]).to eq(pegasus_data[:wings_length])
        expect(event.get("tail")['tail_length']).to eq(tail_data[:tail_length])
        expect(event.get("tail")['braided']['braiding_style']).to eq(braid_data[:braiding_style])
        expect(event.get("@metadata")["pb_oneof"]["horse_type"]).to eq("pegasus")
        expect(event.get("@metadata")["pb_oneof"]["tail"]["hair_type"]).to eq("braided")

      end
    end # it

  end # context pb3decoder_test8a

  ##################################################

  context "#pb3decoder_test8b" do

    # same test as 8a just with different one_of options selected

    let(:plugin_8b) { LogStash::Codecs::Protobuf.new("class_name" => "FantasyHorse", "class_file" => 'pb3/FantasyHorse_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => false)  }
    before do
        plugin_8b.register
    end

    it "should not add meta information on oneof fields" do
      pegasus_data = {:wings_length => 100}
      horsey = FantasyPegasus.new(pegasus_data)

      braid_data = {:braid_thickness => 10, :braiding_style => "french"}
      tail_data = {:tail_length => 80, :braided => BraidedHorseTail.new(braid_data) }
      tail = FantasyHorseTail.new(tail_data)

      data = {:name=>"Winfried", :pegasus => horsey, :tail => tail}
      pb_obj = FantasyHorse.new(data)
      bin = FantasyHorse.encode(pb_obj)
      plugin_8b.decode(bin) do |event|
        expect(event.get("name")).to eq(data[:name])
        expect(event.get("pegasus")["wings_length"]).to eq(pegasus_data[:wings_length])
        expect(event.get("tail")['tail_length']).to eq(tail_data[:tail_length])
        expect(event.get("tail")['braided']['braiding_style']).to eq(braid_data[:braiding_style])
        expect(event.get("@metadata")["pb_oneof"]).to be_nil

      end
    end # it

  end # context pb3decoder_test8b

  ##################################################
    
  context "#pb3decoder_test8c" do 

    # activate the meta info for the one-ofs

    let(:plugin_8c) { LogStash::Codecs::Protobuf.new("class_name" => "FantasyHorse", "class_file" => 'pb3/FantasyHorse_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)  }
    before do
        plugin_8c.register
    end

    it "should add meta information on oneof fields" do
      unicorn_data = {:horn_length => 30}
      horsey = FantasyUnicorn.new(unicorn_data)

      natural_data = {:wavyness => "B"}
      tail_data = {:natural => NaturalHorseTail.new(natural_data) }
      tail = FantasyHorseTail.new(tail_data)

      data = {:name=>"Hubert", :unicorn => horsey, :tail => tail}
      pb_obj = FantasyHorse.new(data)
      bin = FantasyHorse.encode(pb_obj)
      plugin_8c.decode(bin) do |event|
        expect(event.get("name")).to eq(data[:name])
        expect(event.get("unicorn")["horn_length"]).to eq(unicorn_data[:horn_length])
        # TODO expect(event.get("unicorn")["horn_colour"]).to be_nil
        # TODO expect(event.get("tail")['tail_length']).to be_nil
        expect(event.get("tail")['natural']['wavyness']).to eq(natural_data[:wavyness])
        expect(event.get("@metadata")["pb_oneof"]["horse_type"]).to eq("unicorn")
        expect(event.get("@metadata")["pb_oneof"]["tail"]["hair_type"]).to eq("natural")
      end
    end # it

  end # context pb3decoder_test8c

  ##################################################
    
  context "#pb3decoder_test9a" do

    let(:plugin_9) { LogStash::Codecs::Protobuf.new("class_name" => "messages.SendJsonRequest", "class_file" => 'pb3/struct_test_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => false)  }
    before do
        plugin_9.register
    end

    it "should decode a message with an embedded struct" do
      # nested struct field
      struct = Google::Protobuf::Struct.new(fields: {"field_a" => {:string_value => "value_a"}},)
      data = {:UserID=>"123-456", :Details => struct}
      pb_obj = Messages::SendJsonRequest.new(data)
      bin = Messages::SendJsonRequest.encode(pb_obj)

      plugin_9.decode(bin) do |event|
        expect(event.get("@metadata")["pb_oneof"]).to be_nil
        expect(event.get("UserID")).to eq(data[:UserID])
        expect(event.get("Details")).to eq({"field_a"=>"value_a"})
      end
    end # it
  end # context pb3decoder_test9a

  context "#pb3decoder_test9b" do # same as 9a but with one-of metainfo activated

    let(:plugin_9) { LogStash::Codecs::Protobuf.new("class_name" => "messages.SendJsonRequest", "class_file" => 'pb3/struct_test_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)}
    before do
        plugin_9.register
    end

    it "should decode a message with an embedded struct" do
      # nested struct field
      details = Google::Protobuf::Struct.new(
        fields: {"field_a" => {:string_value => "value_a"}},
      )
      data = {:UserID=>"123-456", :Details => details}
      pb_obj = Messages::SendJsonRequest.new(data)
      bin = Messages::SendJsonRequest.encode(pb_obj)

      plugin_9.decode(bin) do |event|
        expect(event.get("@metadata")["pb_oneof"]).to eq({})
        expect(event.get("UserID")).to eq(data[:UserID])
        expect(event.get("Details")).to eq({"field_a"=>"value_a"})
      end
    end # it
  end # context pb3decoder_test9b

  ##################################################
  
  context "#pb3decoder_test10a" do

    let(:plugin_10) { LogStash::Codecs::Protobuf.new("class_name" => "ProtoResultListCompositionCriteria", "class_file" => 'pb3/ResultListComposerRequest_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true) }
    before do
        plugin_10.register
    end

    it "should have only one option set for a double-choice oneOf" do
      input_criterion = {:sort_criterion => "descending", :top_accommodation_id => 4711}
      pb_obj = ProtoResultListCompositionCriteria.new(input_criterion)

      bin = ProtoResultListCompositionCriteria.encode(pb_obj)
      plugin_10.decode(bin) do |event|
        expect(event.get("sort_criterion")).to eq(input_criterion[:sort_criterion])
        expect(event.get("top_accommodation_id")).to eq(input_criterion[:top_accommodation_id])
        expect(event.get("recommend_similar_accommodation_id")).to be_nil
        expect(event.get("@metadata")["pb_oneof"]['accommodation_id']).to eq("top_accommodation_id")
      end
    end # it
  end # context pb3decoder_test10a


  context "#pb3decoder_test10b" do

    # same as 10a but now as a nested field and with a value that equals the default

    let(:plugin_10) { LogStash::Codecs::Protobuf.new("class_name" => "ProtoResultListComposerRequest", "class_file" => 'pb3/ResultListComposerRequest_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)  }
    before do
        plugin_10.register
    end

    it "should have only one option set for a nested double-choice oneOf" do
      input_criterion = {:sort_criterion => "descending", :top_accommodation_id => 0}
      input_resultlist = {:metadata => [], :page_number => 3, :results_per_page => 100, 
          :result_list_composition_criteria => ProtoResultListCompositionCriteria.new(input_criterion)}
      pb_obj = ProtoResultListComposerRequest.new(input_resultlist)

      bin = ProtoResultListComposerRequest.encode(pb_obj)
      plugin_10.decode(bin) do |event|
        expect(event.get("@metadata")["pb_oneof"]['result_list_composition_criteria']['accommodation_id']).to eq('top_accommodation_id')
        expect(event.get("page_number")).to eq(input_resultlist[:page_number])
        expect(event.get("results_per_page")).to eq(input_resultlist[:results_per_page])
        expect(event.get("metadata")).to eq(input_resultlist[:metadata])
        expect(event.get("result_list_composition_criteria")["sort_criterion"]).to eq(input_criterion[:sort_criterion])
        expect(event.get("result_list_composition_criteria")["top_accommodation_id"]).to eq(input_criterion[:top_accommodation_id])
        expect(event.get("result_list_composition_criteria")["recommend_similar_accommodation_id"]).to be_nil
      end
    end # it
  end # context pb3decoder_test10b

  ##################################################

  context "#pb3decoder_test11" do

    # XOR test for one-of but this time with objects instead of scalars, also triple-option of which only 1 must be set.

    let(:plugin_11) { LogStash::Codecs::Protobuf.new("class_name" => "FantasyHorse", "class_file" => 'pb3/FantasyHorse_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => false)  }
    before do
        plugin_11.register
    end

    it "should have only one option set for a triple-choice oneOf" do
      pegasus_data = {:wings_length => 200}
      horsey = FantasyPegasus.new(pegasus_data)

      braid_data = {:braid_thickness => 3, :braiding_style => "french"}
      tail_data = {:tail_length => 80, :braided => BraidedHorseTail.new(braid_data) }
      tail = FantasyHorseTail.new(tail_data)

      data = {:name=>"Reinhold", :pegasus => horsey, :tail => tail}
      pb_obj = FantasyHorse.new(data)
      bin = FantasyHorse.encode(pb_obj)
      plugin_11.decode(bin) do |event|
        expect(event.get("name")).to eq(data[:name])
        expect(event.get("pegasus")["wings_length"]).to eq(pegasus_data[:wings_length])
        expect(event.get("tail")['tail_length']).to eq(tail_data[:tail_length])
        expect(event.get("tail")['braided']['braiding_style']).to eq(braid_data[:braiding_style])
        expect(event.get("tail")['natural']).to be_nil
        expect(event.get("tail")['short']).to be_nil
        expect(event.get("tail")['hair_type']).to be_nil
        expect(event.get("@metadata")["pb_oneof"]).to be_nil
      end
    end # it
  end # context pb3decoder_test11

  ##################################################

  context "#pb3decoder_test12" do
    # One-of metadata with nested class names. Class lookup in the pb descriptor pool has previously been an issue.
    let(:plugin_12) { LogStash::Codecs::Protobuf.new("class_name" => "company.communication.directories.PhoneDirectory", "class_file" => 'pb3/PhoneDirectory_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)  }
    before do
        plugin_12.register
    end

    it "should do one-of meta info lookup for nested classes" do
      contacts = []
      hans = {:name => "Hans Test", :address => "Test street 12, 90210 Test hills", :prefered_email => "hans@test.com"}
      contacts << Company::Communication::Directories::Contact.new(hans)
      jane = {:name => "Jane Trial", :address => "Test street 13, 90210 Test hills", :prefered_phone => 1234567}
      contacts << Company::Communication::Directories::Contact.new(jane)
      kimmy = {:name => "Kimmy Experiment", :address => "Test street 14, 90210 Test hills", :prefered_fax => 666777888}
      contacts << Company::Communication::Directories::Contact.new(kimmy)

      data = {:last_updated_timestamp=>1900000000, :internal => true, :contacts => contacts}
      pb_obj = Company::Communication::Directories::PhoneDirectory.new(data)
      bin = Company::Communication::Directories::PhoneDirectory.encode(pb_obj)
      plugin_12.decode(bin) do |event|
        puts "HELLO RSPEC #{event.to_hash}"
        expect(event.get("internal")).to eq(data[:internal])
        expect(event.get("external")).to be_nil
        expect(event.get("@metadata")["scope"]).to eq('internal')

        expect(event.get("contacts")[0]["name"]).to eq(hans[:name])
        expect(event.get("contacts")[0]["address"]).to eq(hans[:address])
        expect(event.get("contacts")[0]["prefered_email"]).to eq(hans[:prefered_email])
        expect(event.get("contacts")[0]["prefered_fax"]).to be_nil
        expect(event.get("contacts")[0]["prefered_phone"]).to be_nil
        expect(event.get("@metadata")["contacts"][0]['prefered_contact']).to eq('prefered_email')
    
        expect(event.get("contacts")[1]["name"]).to eq(jane[:name])
        expect(event.get("contacts")[1]["address"]).to eq(jane[:address])
        expect(event.get("contacts")[1]["prefered_phone"]).to eq(jane[:prefered_email])
        expect(event.get("contacts")[1]["prefered_fax"]).to be_nil
        expect(event.get("contacts")[1]["prefered_email"]).to be_nil
        expect(event.get("@metadata")["contacts"][1]['prefered_contact']).to eq('prefered_phone')

        expect(event.get("contacts")[2]["name"]).to eq(kimmy[:name])
        expect(event.get("contacts")[2]["address"]).to eq(kimmy[:address])
        expect(event.get("contacts")[2]["prefered_fax"]).to eq(kimmy[:prefered_email])
        expect(event.get("contacts")[2]["prefered_email"]).to be_nil
        expect(event.get("contacts")[2]["prefered_phone"]).to be_nil
        expect(event.get("@metadata")["contacts"][2]['prefered_contact']).to eq('prefered_fax')
    
      end
    end # it
  end # context pb3decoder_test11

  ##################################################

end # describe
