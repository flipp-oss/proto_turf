# frozen_string_literal: true

require 'proto_turf/schema/base'
require 'proto_turf/output/json_schema'

class ProtoTurf
  module Schema
    class ProtoJsonSchema < Base
      class << self
        def schema_type
          'JSON'
        end

        def schema_text(message)
          ProtoTurf::Output::JsonSchema.output(message.class.descriptor.to_proto)
        end

        def encode(message, stream, schema_name: nil)
          json = message.to_h.sort.to_h.to_json
          stream.write(json)
        end

        def decode(stream, _schema)
          json = stream.read
          JSON.parse(json)
        end
      end
    end
  end
end
