# frozen_string_literal: true

require 'logger'
require 'json'
require 'proto_turf/confluent_schema_registry'
require 'proto_turf/cached_confluent_schema_registry'
require 'proto_turf/schema/proto'
require 'proto_turf/schema/json'

class ProtoTurf
  class SchemaNotFoundError < StandardError; end

  # Provides a way to encode and decode messages without having to embed schemas
  # in the encoded data. Confluent's Schema Registry[1] is used to register
  # a schema when encoding a message -- the registry will issue a schema id that
  # will be included in the encoded data alongside the actual message. When
  # decoding the data, the schema id will be used to look up the writer's schema
  # from the registry.
  #
  # 1: https://github.com/confluentinc/schema-registry
  # https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/serdes-protobuf.html
  # https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html#wire-format
  MAGIC_BYTE = [0].pack('C').freeze

  # Instantiate a new ProtoTurf instance with the given configuration.
  #
  # registry             - A schema registry object that responds to all methods in the
  #                        ProtoTurf::ConfluentSchemaRegistry interface.
  # registry_url         - The String URL of the schema registry that should be used.
  # schema_context       - Schema registry context name (optional)
  # registry_path_prefix - The String URL path prefix used to namespace schema registry requests (optional).
  # logger               - The Logger that should be used to log information (optional).
  # proxy                - Forward the request via  proxy (optional).
  # user                 - User for basic auth (optional).
  # password             - Password for basic auth (optional).
  # ssl_ca_file          - Name of file containing CA certificate (optional).
  # client_cert          - Name of file containing client certificate (optional).
  # client_key           - Name of file containing client private key to go with client_cert (optional).
  # client_key_pass      - Password to go with client_key (optional).
  # client_cert_data     - In-memory client certificate (optional).
  # client_key_data      - In-memory client private key to go with client_cert_data (optional).
  # connect_timeout      - Timeout to use in the connection with the schema registry (optional).
  # resolv_resolver      - Custom domain name resolver (optional).
  # schema_type          - PROTOBUF or JSON.
  def initialize( # rubocop:disable Metrics/ParameterLists
    registry: nil,
    registry_url: nil,
    schema_context: nil,
    registry_path_prefix: nil,
    logger: nil,
    proxy: nil,
    user: nil,
    password: nil,
    ssl_ca_file: nil,
    client_cert: nil,
    client_key: nil,
    client_key_pass: nil,
    client_cert_data: nil,
    client_key_data: nil,
    connect_timeout: nil,
    resolv_resolver: nil,
    schema_type: 'PROTOBUF'
  )
    @logger = logger || Logger.new($stderr)
    @registry = registry || ProtoTurf::CachedConfluentSchemaRegistry.new(
      ProtoTurf::ConfluentSchemaRegistry.new(
        registry_url,
        schema_context: schema_context,
        logger: @logger,
        proxy: proxy,
        user: user,
        password: password,
        ssl_ca_file: ssl_ca_file,
        client_cert: client_cert,
        client_key: client_key,
        client_key_pass: client_key_pass,
        client_cert_data: client_cert_data,
        client_key_data: client_key_data,
        path_prefix: registry_path_prefix,
        connect_timeout: connect_timeout,
        resolv_resolver: resolv_resolver
      )
    )
    @schema = schema_type.to_s == 'JSON' ? ProtoTurf::Schema::Json : ProtoTurf::Schema::Proto
  end

  # Encodes a message using the specified schema.
  # @param message [Object] The message that should be encoded. Must be compatible with the schema.
  # @param subject [String] The subject name the schema should be registered under in the schema registry (optional).
  # @return [String] the encoded data.
  def encode(message, subject: nil, schema_text: nil)
    id = register_schema(message, subject, schema_text: schema_text)

    stream = StringIO.new
    # Always start with the magic byte.
    stream.write(MAGIC_BYTE)

    # The schema id is encoded as a 4-byte big-endian integer.
    stream.write([id].pack('N'))

    @schema.encode(message, stream)
    stream.string
  end

  # Decodes data into the original message.
  #
  # @param data [String] a string containing encoded data.
  # @return [Object] the decoded data.
  def decode(data)
    stream = StringIO.new(data)

    # The first byte is MAGIC!!!
    magic_byte = stream.read(1)

    raise "Expected data to begin with a magic byte, got `#{magic_byte.inspect}`" if magic_byte != MAGIC_BYTE

    # The schema id is a 4-byte big-endian integer.
    schema_id = stream.read(4).unpack1('N')
    schema = @registry.fetch(schema_id)
    @schema.decode(stream, schema)
  rescue Excon::Error::NotFound
    raise SchemaNotFoundError, "Schema with id: #{schema_id} is not found on registry"
  end

  private

  def register_schema(message, subject, schema_text: nil)
    schema_text ||= @schema.schema_text(message)
    return if @registry.registered?(schema_text, subject)

    # register dependencies first
    dependencies = @schema.dependencies(message)
    versions = dependencies.map do |name, dependency|
      result = register_schema(dependency, name)
      @registry.fetch_version(result, name)
    end

    @registry.register(subject,
                       schema_text,
                       references: dependencies.keys.map.with_index do |dependency, i|
                         {
                           name: dependency,
                           subject: dependency,
                           version: versions[i]
                         }
                       end,
                       schema_type: @schema.schema_type)
  end
end
