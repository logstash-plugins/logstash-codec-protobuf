# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"

require 'google/protobuf' # for protobuf3

# absolute path to the protobuf helpers directory
pb_include_path = File.expand_path(".") + "/spec/helpers"

require pb_include_path + '/pb3/unicorn_pb.rb'
unicorn_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass

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
  end # context

  context "#pb3decoder_test1" do


    #### Test case 1: Decode simple protobuf ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new(
      "class_name" => "Unicorn", "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)
    }

    it "should return an event from protobuf data" do

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
  end # context

  context "#pb3decoder_test2" do

    #### Test case 2: decode nested protobuf ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)  }

    it "should return an event from protobuf data with nested classes" do
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

  end # context

  context "#pb3decoder_test3" do

    #### Test case 3: decode ProbeResult ####################################################################################################################
    let(:plugin_3) { LogStash::Codecs::Protobuf.new("class_name" => "ProbeResult", "include_path" => [pb_include_path + '/pb3/ProbeResult_pb.rb'], "protobuf_version" => 3)  }

    before do
        plugin_3.register
    end

    it "should return an event from protobuf data with nested classes" do

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
  end # context

  context "#pb3decoder_test4" do

    #### Test case 4: decode PBDNSMessage ####################################################################################################################
    let(:plugin_4) { LogStash::Codecs::Protobuf.new("class_name" => "PBDNSMessage", "include_path" => [pb_include_path + '/pb3/dnsmessage_pb.rb'], "protobuf_version" => 3)  }

    before do
        plugin_4.register
    end

    it "should return an event from protobuf data with nested classes" do


      pbdns_message_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("PBDNSMessage").msgclass
      dns_question_class  = Google::Protobuf::DescriptorPool.generated_pool.lookup("PBDNSMessage.DNSQuestion").msgclass
      dns_response_class  = Google::Protobuf::DescriptorPool.generated_pool.lookup("PBDNSMessage.DNSResponse").msgclass
      dns_rr_class        = Google::Protobuf::DescriptorPool.generated_pool.lookup("PBDNSMessage.DNSResponse.DNSRR").msgclass

      dns_question_data = {:qName => "Foo", :qType => 12345, :qClass => 67890 }
      dns_question_object = dns_question_class.new(dns_question_data)

      dns_response_data = {:rcode => 12345, :appliedPolicy => "baz", :tags => ["a","b","c"],
        :queryTimeSec => 123, :queryTimeUsec => 456,
        :appliedPolicyType => PBDNSMessage::PolicyType::NSIP}

      dns_rr_data = [
        {:name => "abc", :type => 9000, :class => 8000, :ttl => 20, :rdata => "300"},
        {:name => "def", :type => 19000, :class => 18000, :ttl => 120, :rdata => "1300"}
      ]

      dns_response_data[:rrs] = dns_rr_data.map { | d | d = dns_rr_class.new(d) }
      dns_response_object = dns_response_class.new(dns_response_data)

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
      pbdns_message_object = pbdns_message_class.new(pbdns_message_data)
      bin = pbdns_message_class.encode(pbdns_message_object)
      plugin_4.decode(bin) do |event|

        ['messageId', 'serverIdentity','from','to','inBytes','timeUsec','timeSec','id', 'originalRequestorSubnet', 'requestorId' ,'initialRequestId','deviceIdf'].each { |n|
          expect(event.get(n)).to eq(pbdns_message_data[n.to_sym] ) }

        # enum test:
        expect(event.get("type") ).to eq("DNSIncomingResponseType" )
        expect(event.get("socketFamily") ).to eq("INET6" )
        expect(event.get("socketProtocol") ).to eq("TCP" )

        expect(event.get("question")["qName"] ).to eq(dns_question_data[:qName] )
        expect(event.get("question")["qType"] ).to eq(dns_question_data[:qType] )
        expect(event.get("question")["qClass"] ).to eq(dns_question_data[:qClass] )

        ['rcode', 'appliedPolicy','tags','queryTimeSec','queryTimeUsec'].each { |n|   expect(event.get('response')[n]).to eq(dns_response_data[n.to_sym] )   }
        expect(event.get("response")['appliedPolicyType'] ).to eq("NSIP" )

        dns_rr_data.each_with_index { | data, index |
          found = event.get("response")['rrs'][index]
          ['name', 'type','class','ttl','rdata'].each { |n|   expect(found[n]).to eq(data[n.to_sym])   }
        }

      end
    end # it

  end # context

  context "#pb3decoder_test5" do

    #### Test case 5: decode test case for github issue 17 ####################################################################################################################
    let(:plugin_5) { LogStash::Codecs::Protobuf.new("class_name" => "com.foo.bar.IntegerTestMessage", "include_path" => [pb_include_path + '/pb3/integertest_pb.rb'], "protobuf_version" => 3)  }

    before do
      plugin_5.register
    end

    it "should return an event from protobuf data with nested classes" do
      integertest_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("com.foo.bar.IntegerTestMessage").msgclass
      integertest_object = integertest_class.new({:response_time => 500})
      bin = integertest_class.encode(integertest_object)
      plugin_5.decode(bin) do |event|
        expect(event.get("response_time") ).to eq(500)
      end
    end # it


  end # context

  context "#pb3decoder_test6" do


    let(:execution_context) { double("execution_context")}
    let(:pipeline_id) {rand(36**8).to_s(36)}

    # Test case 6: decode a message automatically loading the dependencies ##############################################################################
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

      header_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("Header").msgclass
      header_data = {:name => {'a' => 'b'}}
      header_object = header_class.new(header_data)

      message_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("A.MessageA").msgclass
      data = {:name => "Test name", :header => header_object}

      message_object = message_class.new(data)
      bin = message_class.encode(message_object)

      plugin.decode(bin) do |event|
        expect(event.get("name") ).to eq(data[:name] )
        expect(event.get("header")['name'] ).to eq(header_data[:name])
      end
    end # it
  end # context






  context "#pb3decoder_test7" do

    #### Test case 6: decode test case for github issue 17 ####################################################################################################################
    let(:plugin_7) { LogStash::Codecs::Protobuf.new("class_name" => "RepeatedEvents", "include_path" => [pb_include_path + '/pb3/events_pb.rb'], "protobuf_version" => 3)  }
    before do
        plugin_7.register
    end

    it "should return an event from protobuf data with repeated top level objects" do
      event_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("RepeatedEvent").msgclass # TODO this shouldnt be necessary because the classes are already
      # specified at the end of the _pb.rb files
      events_class = Google::Protobuf::DescriptorPool.generated_pool.lookup("RepeatedEvents").msgclass
      test_a = event_class.new({:id => "1", :msg => "a"})
      test_b = event_class.new({:id => "2", :msg => "b"})
      test_c = event_class.new({:id => "3", :msg => "c"})
      event_obj = events_class.new({:repeated_events=>[test_a, test_b, test_c]})
      bin = events_class.encode(event_obj)
      plugin_7.decode(bin) do |event|
        expect(event.get("repeated_events").size ).to eq(3)
        expect(event.get("repeated_events")[0]["id"] ).to eq("1")
        expect(event.get("repeated_events")[2]["id"] ).to eq("3")
        expect(event.get("repeated_events")[0]["msg"] ).to eq("a")
        expect(event.get("repeated_events")[2]["msg"] ).to eq("c")
      end
    end # it


  end # context pb3decoder_test7


  context "#pb3decoder_test8a" do

    ########################################################################################################################
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

        expect(event.get("name") ).to eq(data[:name])
        expect(event.get("pegasus")["wings_length"] ).to eq(pegasus_data[:wings_length])
        expect(event.get("tail")['tail_length'] ).to eq(tail_data[:tail_length])
        expect(event.get("tail")['braided']['braiding_style'] ).to eq(braid_data[:braiding_style])
        expect(event.get("@metadata")["pb_oneof"]["horse_type"] ).to eq("pegasus")
        expect(event.get("@metadata")["pb_oneof"]["tail"]["hair_type"] ).to eq("braided")

      end
    end # it


  end # context pb3decoder_test8a




  context "#pb3decoder_test8b" do

    ########################################################################################################################
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
        expect(event.get("name") ).to eq(data[:name])
        expect(event.get("pegasus")["wings_length"] ).to eq(pegasus_data[:wings_length])
        expect(event.get("tail")['tail_length'] ).to eq(tail_data[:tail_length])
        expect(event.get("tail")['braided']['braiding_style'] ).to eq(braid_data[:braiding_style])
        expect(event.get("@metadata")["pb_oneof"]).to be_nil

      end
    end # it


  end # context pb3decoder_test8b


  context "#pb3decoder_test8c" do # same test as 8a just with different one_of options selected

    ########################################################################################################################
    let(:plugin_8c) { LogStash::Codecs::Protobuf.new("class_name" => "FantasyHorse", "class_file" => 'pb3/FantasyHorse_pb.rb',
      "protobuf_root_directory" => pb_include_path, "protobuf_version" => 3, "pb3_set_oneof_metainfo" => true)  }
    before do
        plugin_8c.register
    end

    it "should add meta information on oneof fields" do
      unicorn_data = {:horn_length => 30}
      horsey = FantasyUnicorn.new(unicorn_data)

      natural_data = {:wavyness => "B"}
      tail_data = {:tail_length => 80, :natural => NaturalHorseTail.new(natural_data) }
      tail = FantasyHorseTail.new(tail_data)

      data = {:name=>"Hubert", :unicorn => horsey, :tail => tail}
      pb_obj = FantasyHorse.new(data)
      bin = FantasyHorse.encode(pb_obj)
      plugin_8c.decode(bin) do |event|
        expect(event.get("name") ).to eq(data[:name])
        expect(event.get("unicorn")["horn_length"] ).to eq(unicorn_data[:horn_length])
        expect(event.get("tail")['tail_length'] ).to eq(tail_data[:tail_length])
        expect(event.get("tail")['natural']['wavyness'] ).to eq(natural_data[:wavyness])
        expect(event.get("@metadata")["pb_oneof"]["horse_type"] ).to eq("unicorn")
        expect(event.get("@metadata")["pb_oneof"]["tail"]["hair_type"] ).to eq("natural")

      end
    end # it


  end # context pb3decoder_test8c

end # describe
