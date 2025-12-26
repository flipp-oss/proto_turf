# frozen_string_literal: true

class ProtoTurf
  module Schema
    class MissingImplementationError < StandardError; end

    class Base
      class << self
        # @param message [Object]
        # @return [String]
        def schema_text(_message)
          raise MissingImplementationError, 'Subclasses must implement schema_text'
        end

        # @return [String]
        def schema_type
          raise MissingImplementationError, 'Subclasses must implement schema_type'
        end

        # @param message [Object]
        # @param stream [StringIO]
        def encode(_message, _stream)
          raise MissingImplementationError, 'Subclasses must implement encode'
        end

        # @param stream [StringIO]
        # @param schema [Object]
        # @return [Object]
        def decode(_stream, _schema)
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
