# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: messageB.proto3

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "B.MessageB" do
    optional :name, :string, 1
    optional :header, :string, 2
  end
end

module B
  MessageB = Google::Protobuf::DescriptorPool.generated_pool.lookup("B.MessageB").msgclass
end
