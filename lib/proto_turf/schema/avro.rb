# frozen_string_literal: true

require 'proto_turf/schema/base'
require 'proto_turf/avro_schema_store'

class ProtoTurf
  module Schema
    class Avro < Base

      DEFAULT_SCHEMAS_PATH = './schemas'.freeze

      class << self
        def schema_type
          'AVRO'
        end

        def schema_store
          @schema_store ||= ProtoTurf::AvroSchemaStore.new(
            path: ProtoTurf.avro_schema_path || DEFAULT_SCHEMAS_PATH
          )
          @schema_store.load_schemas!
          @schema_store
        end

        def schema_text(_message, schema_name: nil)
          schema_store.find_text(schema_name)
        end

        def encode(message, stream, schema_name: nil)
          validate_options = {recursive: true,
                             encoded: false,
                             fail_on_extra_fields: true}
          schema = schema_store.find(schema_name)

          ::Avro::SchemaValidator.validate!(schema, message, **validate_options)

          writer = ::Avro::IO::DatumWriter.new(schema)
          encoder = ::Avro::IO::BinaryEncoder.new(stream)
          writer.write(message, encoder)
        end

        def decode(stream, schema_text)
          # Parse the schema text from the registry into an Avro schema object
          schema_json = JSON.parse(schema_text)
          writers_schema = ::Avro::Schema.parse(schema_text)

          decoder = ::Avro::IO::BinaryDecoder.new(stream)

          # Try to find the reader schema locally, fall back to writer schema
          readers_schema = begin
            schema_store.find(writers_schema.fullname)
          rescue
            writers_schema
          end

          reader = ::Avro::IO::DatumReader.new(writers_schema, readers_schema)
          reader.read(decoder)
        end
      end
    end
  end
end
