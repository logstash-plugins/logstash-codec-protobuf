# Generated by the protocol buffer compiler.  DO NOT EDIT!

begin; require 'google/protobuf'; rescue LoadError; end

begin; require 'header/header_pb'; rescue LoadError; end
Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "ProtoAkamaiEtid" do
    optional :header, :message, 1, "Header"
    optional :version, :string, 2
    optional :method, :string, 3
    optional :uri, :string, 4
    optional :status, :uint32, 5
    optional :response_bytes, :uint32, 6
    optional :transfer_time, :uint32, 7
    optional :referrer, :string, 8
    optional :user_agent, :string, 9
    optional :cookie, :string, 10
    optional :etid, :string, 11
    optional :ghostip, :string, 12
    optional :cache_status, :uint32, 13
    optional :timestamp, :string, 15
    optional :warp, :bool, 16
    optional :hostname, :string, 17
    optional :bucket, :string, 18
  end
end


module EtidAkamai
    ProtoAkamaiEtid = Google::Protobuf::DescriptorPool.generated_pool.lookup("EtidAkamai.ProtoAkamaiEtid").msgclass
end
