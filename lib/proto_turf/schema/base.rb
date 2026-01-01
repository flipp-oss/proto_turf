# frozen_string_literal: true

class ProtoTurf
  module Schema
    class MissingImplementationError < StandardError; end

    class Base
      class << self
        # @param message [Object]
        # @param schema_name [String]
        # @return [String]
        def schema_text(_message, schema_name: nil)
          raise MissingImplementationError, 'Subclasses must implement schema_text'
        end

        # @return [String]
        def schema_type
          raise MissingImplementationError, 'Subclasses must implement schema_type'
        end

        # @param message [Object]
        # @param stream [StringIO]
        # @param schema_name [String]
        def encode(_message, _stream, schema_name: nil)
          raise MissingImplementationError, 'Subclasses must implement encode'
        end

        # @param stream [StringIO]
        # @param schema_text [String]
        # @param registry [Object]
        # @return [Object]
        def decode(_stream, _schema_text)
          raise MissingImplementationError, 'Subclasses must implement decode'
        end

        # @param message [Object]
        # @return [Hash<String, String>]
        def dependencies(_message)
          {}
        end
      end
    end
  end
end
