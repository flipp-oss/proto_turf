# frozen_string_literal: true

require 'google/protobuf'
require 'google/protobuf/well_known_types'
require 'google/protobuf/descriptor_pb'
require 'proto_turf/output/proto_text'
require 'proto_turf/schema/base'
require 'proto_turf/wire'

class ProtoTurf
  module Schema
    class Protobuf < Base
      class << self
        def schema_type
          'PROTOBUF'
        end

        def schema_text(message)
          file_descriptor = if message.is_a?(Google::Protobuf::FileDescriptor)
                              message
                            else
                              message.class.descriptor.file_descriptor
                            end
          ProtoTurf::Output::ProtoText.output(file_descriptor.to_proto)
        end

        def encode(message, stream, schema_name: nil)
          _, indexes = find_index(message.class.descriptor.to_proto,
                                  message.class.descriptor.file_descriptor.to_proto.message_type)

          if indexes == [0]
            ProtoTurf::Wire.write_int(stream, 0)
          else
            ProtoTurf::Wire.write_int(stream, indexes.length)
            indexes.each { |i| ProtoTurf::Wire.write_int(stream, i) }
          end

          # Now we write the actual message.
          stream.write(message.to_proto)
        end

        def decode(stream, schema)
          # See https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html#wire-format
          index_length = ProtoTurf::Wire.read_int(stream)
          indexes = []
          if index_length.zero?
            indexes.push(0)
          else
            index_length.times do
              indexes.push(ProtoTurf::Wire.read_int(stream))
            end
          end

          encoded = stream.read
          decode_protobuf(schema, encoded, indexes)
        end

        def load_schemas!
          @all_schemas = {}
          all_files = ObjectSpace.each_object(Google::Protobuf::FileDescriptor).to_a
          all_files.each do |file_desc|
            file_path = file_desc.name
            next if file_path.start_with?('google/protobuf/') # skip built-in protos

            @all_schemas[file_path] = file_desc
          end
        end

        def dependencies(message)
          load_schemas! unless @all_schemas&.any?
          file_descriptor = if message.is_a?(Google::Protobuf::FileDescriptor)
                              message
                            else
                              message.class.descriptor.file_descriptor
                            end

          deps = file_descriptor.to_proto.dependency.to_a
                                .reject { |d| d.start_with?('google/protobuf/') }
          deps.to_h do |dep|
            dependency_schema = @all_schemas[dep]
            [dependency_schema.name, dependency_schema]
          end
        end

        def find_index(descriptor, messages, indexes = [])
          messages.each_with_index do |sub_descriptor, i|
            if sub_descriptor == descriptor
              indexes.push(i)
              return [true, indexes]
            else
              found, found_indexes = find_index(descriptor, sub_descriptor.nested_type, indexes + [i])
              return [true, found_indexes] if found
            end
          end
          []
        end

        def find_descriptor(indexes, messages)
          first_index = indexes.shift
          message = messages[first_index]
          path = [message.name]
          while indexes.length.positive?
            message = message.nested_type[indexes.shift]
            path.push(message.name)
          end
          path
        end

        def decode_protobuf(schema, encoded, indexes)
          # get the package
          package = schema.match(/package (\S+);/)[1]
          # get the first message in the protobuf text
          # TODO - get the correct message based on schema index
          message_name = schema.match(/message (\w+) {/)[1]
          # look up the descriptor
          full_name = "#{package}.#{message_name}"
          descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(full_name)
          unless descriptor
            msg = "Could not find schema for #{full_name}. " \
                  'Make sure the corresponding .proto file has been compiled and loaded.'
            raise msg
          end

          path = find_descriptor(indexes, descriptor.file_descriptor.to_proto.message_type)
          correct_message = Google::Protobuf::DescriptorPool.generated_pool.lookup("#{package}.#{path.join('.')}")
          correct_message.msgclass.decode(encoded)
        end
      end
    end
  end
end
