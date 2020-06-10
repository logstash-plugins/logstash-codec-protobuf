# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"

require 'google/protobuf' # for protobuf3

# absolute path to the protobuf helpers directory
pb_include_path = File.expand_path(".") + "/spec/helpers"

describe LogStash::Codecs::Protobuf do

  context "#encodePB3-a" do

    #### Test case 1: encode simple protobuf ####################################################################################################################

    require_relative '../helpers/pb3/unicorn_pb.rb'

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)
    end

    event1 = LogStash::Event.new("name" => "Pinkie", "age" => 18, "is_pegasus" => false, "favourite_numbers" => [1,2,3], "fur_colour" => Colour::PINK, "favourite_colours" => [1,5] )

    it "should return protobuf encoded data for testcase 1" do

      subject.on_event do |event, data|
        expect(data).to be_a(String)

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("Unicorn").msgclass
        decoded_data = pb_builder.decode(data)
        expect(decoded_data.name ).to eq(event.get("name") )
        expect(decoded_data.age ).to eq(event.get("age") )
        expect(decoded_data.is_pegasus ).to eq(event.get("is_pegasus") )
        expect(decoded_data.fur_colour ).to eq(:PINK)
        expect(decoded_data.favourite_numbers ).to eq(event.get("favourite_numbers") )
        expect(decoded_data.favourite_colours ).to eq([:BLUE,:WHITE] )
      end # subject.on_event

      subject.encode(event1)
    end # it

  end # context

  context "#encodePB3-b" do

    #### Test case 2: encode nested protobuf ####################################################################################################################

    require_relative '../helpers/pb3/unicorn_pb.rb'

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "include_path" => [pb_include_path + '/pb3/unicorn_pb.rb'], "protobuf_version" => 3)
    end

    event = LogStash::Event.new("name" => "Horst", "age" => 23, "is_pegasus" => true, "mother" => \
        {"name" => "Mom", "age" => 47}, "father" => {"name"=> "Daddy", "age"=> 50, "fur_colour" => 3 } # 3 == SILVER
      )

    it "should return protobuf encoded data for testcase 2" do

      subject.on_event do |event, data|
        expect(data).to be_a(String)

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
      subject.encode(event)
    end # it

  end # context #encodePB3

  context "encodePB3-c" do

    #### Test case 3: encode nested protobuf ####################################################################################################################


    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "something.rum_akamai.ProtoAkamaiRum", "include_path" => [pb_include_path + '/pb3/rum_pb.rb' ], "protobuf_version" => 3)
    end

    event = LogStash::Event.new(
      "user_agent"=>{"os"=>"Android OS", "family"=>"Chrome Mobile", "major"=>74, "mobile"=>"1", "minor"=>0, "manufacturer"=>"Samsung", "osversion"=>"8",
          "model"=>"Galaxy S7 Edge", "type"=>"Mobile",
          "raw"=>"Mozilla/5.0 (Linux; Android 8.0.0; SM-G935F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Mobile Safari/537.36"},
          "dom"=>{"script"=>65, "ln"=>2063, "ext"=>47}, "page_group"=>"SEO-Pages",
          "active_ctests"=>["1443703219", "47121", "47048", "46906"], "timestamp"=>"1559566982508",
          "geo"=>{"isp"=>"Telecom Italia Mobile", "lat"=>45.4643, "postalcode"=>"20123", "netspeed"=>"Cellular", "rg"=>"MI", "cc"=>"IT",
            "organisation"=>"Telecom Italia Mobile", "ovr"=>false, "city"=>"Milan", "lon"=>9.1895},
          "header"=>{"sender_id"=>"0"}, "domain"=>"something.com", "url"=>"https://www.something.it/",
          "timers"=>{"tti"=>4544, "ttvr"=>3657, "fcp"=>2683, "ttfi"=>4280, "fid"=>31, "longtasks"=>2519, "t_resp"=>1748}
    )

    it "should return protobuf encoded data for testcase 3" do

      subject.on_event do |event, data|
        expect(data).to be_a(String)

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("something.rum_akamai.ProtoAkamaiRum").msgclass
        decoded_data = pb_builder.decode(data)

        expect(decoded_data.domain ).to eq(event.get("domain") )
        expect(decoded_data.dom.ext ).to eq(event.get("dom")["ext"] )
        expect(decoded_data.user_agent.type ).to eq(event.get("user_agent")["type"] )
        expect(decoded_data.geo.rg ).to eq(event.get("geo")["rg"] )


      end # subject4.on_event
      subject.encode(event)
    end # it
  end # context #encodePB3-c


  context "encodePB3-d" do

    #### Test case 3: autoconvert data types ####################################################################################################################


    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "something.rum_akamai.ProtoAkamai2Rum",
        "pb3_encoder_autoconvert_types" => true,
        "include_path" => [pb_include_path + '/pb3/rum2_pb.rb' ], "protobuf_version" => 3)
    end

    event = LogStash::Event.new(

     # major should autoconvert to float
     "user_agent"=>{"minor"=>0,"major"=>"74"},

     # ext should autoconvert to int. script being empty should be ignored.
     "dom"=>{"script"=>nil, "ln"=>2063, "ext"=>47.0},

     # ovr should autoconvert to Boolean
     "geo"=>{"ovr"=>"false"},

     # sender_id should autoconvert to string
     "header"=>{"sender_id"=>1},
     "domain" => "www",

     # should autoconvert to string
     "http_referer" => 1234,
    )


    it "should fix datatypes to match the protobuf definition" do

      subject.on_event do |event, data|
        expect(data).to be_a(String)

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("something.rum_akamai.ProtoAkamai2Rum").msgclass
        decoded_data = pb_builder.decode(data)
        expect(decoded_data.domain ).to eq(event.get("domain") )
        expect(decoded_data.user_agent.major).to eq(74)
        expect(decoded_data.dom.ext).to eq(47)
        expect(decoded_data.geo.ovr).to eq(false)
        expect(decoded_data.header.sender_id).to eq("1")
        expect(decoded_data.http_referer).to eq("1234")

      end
      subject.encode(event)
    end # it

  end # context #encodePB3-d


context "encodePB3-e" do

    #### Test case 4: handle nil data ####################################################################################################################



    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "something.rum_akamai.ProtoAkamai3Rum",
        "pb3_encoder_autoconvert_types" => false,
        "include_path" => [pb_include_path + '/pb3/rum3_pb.rb' ], "protobuf_version" => 3)
    end

    event = LogStash::Event.new(
      "domain" => nil,
      "header" => {"sender_id" => "23"},
      "geo"=>{"organisation"=>"Jio", "rg"=>"DL", "netspeed"=>nil, "city"=>nil, "cc"=>"IN", "ovr"=>false, "postalcode"=>"110012", "isp"=>"Jio"}
    )

    it "should ignore empty fields" do

      subject.on_event do |event, data|
        expect(data).to be_a(String)

        pb_builder = Google::Protobuf::DescriptorPool.generated_pool.lookup("something.rum_akamai.ProtoAkamai3Rum").msgclass
        decoded_data = pb_builder.decode(data)
        expect(decoded_data.geo.organisation ).to eq(event.get("geo")["organisation"])
        expect(decoded_data.geo.ovr ).to eq(event.get("geo")["ovr"])
        expect(decoded_data.geo.postalcode ).to eq(event.get("geo")["postalcode"])
        expect(decoded_data.header.sender_id ).to eq(event.get("header")['sender_id'] )

      end
      subject.encode(event)
    end # it

  end # context #encodePB3-e



context "encodePB3-f" do

    #### Test case 5: handle additional fields (discard event without crashing pipeline) ####################################################################################################################

    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "something.rum_akamai.ProtoAkamai3Rum",
        "pb3_encoder_autoconvert_types" => false,
        "include_path" => [pb_include_path + '/pb3/rum3_pb.rb' ], "protobuf_version" => 3)
    end

    event = LogStash::Event.new(
      "domain" => nil, "bot" => "This field does not exist in the protobuf definition",
      "header" => {"sender_id" => "23"},
      "geo"=>{"organisation"=>"Jio", "rg"=>"DL", "netspeed"=>nil, "city"=>nil, "cc"=>"IN", "ovr"=>false, "postalcode"=>"110012", "isp"=>"Jio"}
    )

    it "should not return data" do

      subject.on_event do |event, data|
        expect("the on_event method should not be called").to eq("so this code should never be reached")
      end
      subject.encode(event)
    end # it

  end # context #encodePB3-f




end # describe
