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

        def decode(stream, schema)
          decoder = ::Avro::IO::BinaryDecoder.new(stream)
          readers_schema = @schema_store.find(schema.fullname)

          reader = ::Avro::IO::DatumReader.new(schema, readers_schema)
          reader.read(decoder)
        end
      end
    end
  end
end
