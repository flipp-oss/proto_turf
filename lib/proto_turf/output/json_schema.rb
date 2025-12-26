# frozen_string_literal: true

class ProtoTurf
  module Output
    module JsonSchema
      class << self
        def fetch(message_name)
          name = message_name.start_with?('.') ? message_name[1..] : message_name
          Google::Protobuf::DescriptorPool.generated_pool.lookup(name)
        end

        def output(descriptor, field: nil)
          properties = {}
          result = {
            '$schema': 'https://json-schema.org/draft/2020-12/schema',
            type: 'object',
            properties: properties,
            required: descriptor.field.reject(&:proto3_optional).map(&:name)
          }
          if field
            properties[field] = field_object(descriptor.field.find { |f| f.name == field.to_s })
          else
            descriptor.field.each do |f|
              properties[f.name] = field_object(f)
            end
          end
          JSON.pretty_generate(result)
        end

        def field_object(field, ignore_repeated: false)
          klass = fetch(field.type_name)
          if field.label == :LABEL_REPEATED && !ignore_repeated
            if klass&.options.respond_to?(:map_entry) && klass.options.map_entry
              return {
                type: 'object',
                additionalProperties: field_object(klass.field[1])
              }
            end
            return {
              type: 'array',
              items: field_object(field, ignore_repeated: true)
            }
          end
          field_type(field, klass)
        end

        def field_type(field, klass)
          case field.type
          when :TYPE_INT32, :TYPE_UINT32, :TYPE_SINT32, :TYPE_FIXED32, :TYPE_SFIXED32
            { type: 'integer' }
          when :TYPE_FLOAT, :TYPE_DOUBLE
            { type: 'number' }
          when :TYPE_INT64, :TYPE_UINT64, :TYPE_SINT64, :TYPE_FIXED64, :TYPE_SFIXED64, :TYPE_STRING, :TYPE_BYTES
            { type: 'string' }
          when :TYPE_BOOL
            { type: 'boolean' }
          else
            if klass.is_a?(Google::Protobuf::EnumDescriptor)
              { enum: klass.to_h.keys }
            else
              { type: 'object' }
            end
          end
        end
      end
    end
  end
end
