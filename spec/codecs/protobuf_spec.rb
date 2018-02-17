# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/codecs/protobuf"
require "logstash/event"
require "insist"


require 'google/protobuf' # for protobuf3
require 'protocol_buffers' # https://github.com/codekitchen/ruby-protocol-buffers, for protobuf2


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
        expect(event.get("fur_colour") ).to eq(data[:fur_colour])
        expect(event.get("favourite_numbers") ).to eq(data[:favourite_numbers] )
        expect(event.get("favourite_colours") ).to eq(data[:favourite_colours] )
        expect(event.get("is_pegasus") ).to eq(data[:is_pegasus] )
      end
    end # it





    #### Test case 2: Decode without enum translation ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Unicorn", "resolve_enums_to_int" => false, "include_path" => ['spec/helpers/pb3/unicorn_pb.rb'], "protobuf_version_3" => true)  }
    before do
        plugin_unicorn.register      
    end

    it "should return an event with enums as symbols" do
    
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

  context "#decodePB2" do


    #### Test case 1: Decode simple protobuf bytes for unicorn ####################################################################################################################
    let(:plugin_unicorn) { LogStash::Codecs::Protobuf.new("class_name" => "Animal::Unicorn", "include_path" => ['spec/helpers/pb2/unicorn.pb.rb'])  }
    before do
        plugin_unicorn.register      
    end

    it "should return an event from protobuf encoded data" do
    
      data = {:colour => 'rainbow', :horn_length => 18, :last_seen => 1420081471, :has_wings => true}
      unicorn = Animal::Unicorn.new(data)
        
      plugin_unicorn.decode(unicorn.serialize_to_string) do |event|
        expect(event.get("colour") ).to eq(data[:colour] )
        expect(event.get("horn_length") ).to eq(data[:horn_length] )
        expect(event.get("last_seen") ).to eq(data[:last_seen] )
        expect(event.get("has_wings") ).to eq(data[:has_wings] )
      end
    end # it



    #### Test case 2: Decode complex protobuf bytes for human #####################################################################################################################


  
 
    let(:plugin_human) { LogStash::Codecs::Protobuf.new("class_name" => "Animal::Human", "include_path" => ['spec/helpers/pb2/human.pb.rb'])  }
    before do
        plugin_human.register      
    end

    it "should return an event from complex nested protobuf encoded data" do
    
      data_gm = {:first_name => 'Elisabeth', :last_name => "Oliveoil", :middle_names => ["Maria","Johanna"], :vegetarian=>true}
      grandmother = Animal::Human.new(data_gm)
      data_m = {:first_name => 'Annemarie', :last_name => "Smørebrød", :mother => grandmother}
      mother = Animal::Human.new(data_m)
      data_f = {:first_name => 'Karl', :middle_names => ["Theodor-Augustin"], :last_name => "Falkenstein"}
      father = Animal::Human.new(data_f)
      data = {:first_name => 'Hugo', :middle_names => ["Heinz", "Peter"], :last_name => "Smørebrød",:father => father, :mother => mother}  
      hugo = Animal::Human.new(data)
       
      plugin_human.decode(hugo.serialize_to_string) do |event|
        expect(event.get("first_name") ).to eq(data[:first_name] )
        expect(event.get("middle_names") ).to eq(data[:middle_names] )
        expect(event.get("last_name") ).to eq(data[:last_name] )
        expect(event.get("[mother][first_name]") ).to eq(data_m[:first_name] ) 
        expect(event.get("[father][first_name]") ).to eq(data_f[:first_name] )
        expect(event.get("[mother][last_name]") ).to eq(data_m[:last_name] )
        expect(event.get("[mother][mother][last_name]") ).to eq(data_gm[:last_name] )
        expect(event.get("[mother][mother][first_name]") ).to eq(data_gm[:first_name] )
        expect(event.get("[mother][mother][middle_names]") ).to eq(data_gm[:middle_names] )
        expect(event.get("[mother][mother][vegetarian]") ).to eq(data_gm[:vegetarian] )
        expect(event.get("[father][last_name]") ).to eq(data_f[:last_name] )
        expect(event.get("[father][middle_names]") ).to eq(data_f[:middle_names] )
      end
    end # it






    #### Test case 3: Decoder test for enums #####################################################################################################################


  
 
    let(:plugin_col) { LogStash::Codecs::Protobuf.new("class_name" => "ColourProtoTest", "include_path" => ['spec/helpers/pb2/ColourTestcase.pb.rb'])  }
    before do
        plugin_col.register      
    end

    it "should return an event from protobuf encoded data with enums" do
    
      data = {:least_liked => ColourProtoTest::Colour::YELLOW, :favourite_colours => \
        [ColourProtoTest::Colour::BLACK, ColourProtoTest::Colour::BLUE], :booleantest => [true, false, true]}  
      pb = ColourProtoTest.new(data)
       
      plugin_col.decode(pb.serialize_to_string) do |event|
        expect(event.get("least_liked") ).to eq(data[:least_liked] )
        expect(event.get("favourite_colours") ).to eq(data[:favourite_colours] )
        expect(event.get("booleantest") ).to eq(data[:booleantest] )
      end
    end # it


  end # context decodePB2





  #### Test case 4: Encode simple protobuf bytes for unicorn ####################################################################################################################

  context "#encodePB2-a" do
    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Animal::UnicornEvent", "include_path" => ['spec/helpers/pb2/unicorn_event.pb.rb']) 
    end

    event = LogStash::Event.new("colour" => "pink", "horn_length" => 12, "last_seen" => 1410081999, "has_wings" => true)    

    it "should return protobuf encoded data from a simple event" do
      subject.on_event do |event, data|
        insist { data.is_a? String }
        unicorn = Animal::UnicornEvent.parse(data) 
    
        expect(unicorn.colour ).to eq(event.get("colour") )
        expect(unicorn.horn_length ).to eq(event.get("horn_length") )
        expect(unicorn.last_seen ).to eq(event.get("last_seen") )
        expect(unicorn.has_wings ).to eq(event.get("has_wings") )
      
      end # subject.on_event
      subject.encode(event)
    end # it
  end # context




  #### Test case 5: encode complex protobuf bytes for human #####################################################################################################################
  
  
  context "#encodePB2-b" do
    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "Animal::Human", "include_path" => ['spec/helpers/pb2/human.pb.rb']) 
    end

    event = LogStash::Event.new("first_name" => "Jimmy", "middle_names" => ["Bob", "James"], "last_name" => "Doe" \
      , "mother" => {"first_name" => "Jane", "middle_names" => ["Elizabeth"], "last_name" => "Doe" , "age" => 83, "vegetarian"=> false} \
      , "father" => {"first_name" => "John", "last_name" => "Doe", "@email" => "character_replacement_test@nothing" })    

    it "should return protobuf encoded data from a complex event" do

      subject.on_event do |event, data|
        insist { data.is_a? String }
        jimmy = Animal::Human.parse(data) 
        
        expect(jimmy.first_name ).to eq(event.get("first_name") )
        expect(jimmy.middle_names ).to eq(event.get("middle_names") )
        expect(jimmy.last_name ).to eq(event.get("last_name") )
        expect(jimmy.mother.first_name ).to eq(event.get("[mother][first_name]") )
        expect(jimmy.father.first_name ).to eq(event.get("[father][first_name]") )
        expect(jimmy.mother.middle_names ).to eq(event.get("[mother][middle_names]") )
        expect(jimmy.mother.age ).to eq(event.get("[mother][age]") ) # recursion test for values
        expect(jimmy.mother.vegetarian ).to eq(event.get("[mother][vegetarian]") ) # recursion test for values
        expect(jimmy.father.last_name ).to eq(event.get("[father][last_name]") )
        expect(jimmy.father.email ).to eq(event.get("[father][@email]") ) # recursion test for keys
        expect(jimmy.mother.last_name ).to eq(event.get("[mother][last_name]") )
      
      end # subject.on_event
      subject.encode(event)
    end # it
  end # context





  #### Test case 6: encode enums #########################################################################################################################
  

 
  context "#encodePB2-c" do
    subject do
      next LogStash::Codecs::Protobuf.new("class_name" => "ColourProtoTest", "include_path" => ['spec/helpers/pb2/ColourTestcase.pb.rb'])
    end

    require 'spec/helpers/pb2/ColourTestcase.pb.rb' # otherwise we cant use the colour enums in the next line
    event = LogStash::Event.new("booleantest" =>  [false, false, true], "least_liked" => ColourProtoTest::Colour::YELLOW,  "favourite_colours" => \
       [ColourProtoTest::Colour::BLACK, ColourProtoTest::Colour::BLUE] )    

    it "should return protobuf encoded data from a complex event with enums" do

      subject.on_event do |event, data|
        insist { data.is_a? String }

        colpref = ColourProtoTest.parse(data) 
        
        expect(colpref.booleantest ).to eq(event.get("booleantest") )
        expect(colpref.least_liked ).to eq(event.get("least_liked") )
        expect(colpref.favourite_colours ).to eq(event.get("favourite_colours") )

      
      end # subject.on_event
      subject.encode(event)
    end # it
  end # context



end # describe
