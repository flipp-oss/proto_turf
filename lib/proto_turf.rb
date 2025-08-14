require 'logger'
require 'proto_turf/schema_store'
require 'proto_turf/confluent_schema_registry'
require 'proto_turf/cached_confluent_schema_registry'

class ProtoTurf
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
  MAGIC_BYTE = [0].pack("C").freeze


  # Instantiate a new ProtoTurf instance with the given configuration.
  #
  # registry             - A schema registry object that responds to all methods in the
  #                        ProtoTurf::ConfluentSchemaRegistry interface.
  # registry_url         - The String URL of the schema registry that should be used.
  # schema_context       - Schema registry context name (optional)
  # schemas_path         - The String file system path where local schemas are stored.
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
  def initialize(
    registry: nil,
    registry_url: nil,
    schema_context: nil,
    schemas_path: nil,
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
    retry_limit: nil
  )
    @logger = logger || Logger.new($stderr)
    @path = schemas_path
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
    @all_schemas = {}
  end

  # Encodes a message using the specified schema.
  #
  # message           - The message that should be encoded. Must be compatible with
  #                     the schema.
  # subject           - The subject name the schema should be registered under in
  #                     the schema registry (optional).
  # Returns the encoded data as a String.
  def encode(message, subject: nil)
    load_schemas! if @all_schemas.empty?

    id = register_schema(message.class.descriptor.file_descriptor, subject: subject)

    stream = StringIO.new
    # Always start with the magic byte.
    stream.write(MAGIC_BYTE)

    # The schema id is encoded as a 4-byte big-endian integer.
    stream.write([id].pack("N"))

    # For now, we're only going to support a single message per schema. See
    # https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html#wire-format
    write_int(stream, 0)

    # Now we write the actual message.
    stream.write(message.to_proto)

    stream.string
  rescue Excon::Error::NotFound
    if schema_id
      raise SchemaNotFoundError.new("Schema with id: #{schema_id} is not found on registry")
    else
      raise SchemaNotFoundError.new("Schema with subject: `#{subject}` version: `#{version}` is not found on registry")
    end
  end

  # Decodes data into the original message.
  #
  # data        - A String containing encoded data.
  #
  # Returns a Protobuf AbstractMessage object instantiated with the decoded data.
  def decode(data)
    stream = StringIO.new(data)

    # The first byte is MAGIC!!!
    magic_byte = stream.read(1)

    if magic_byte != MAGIC_BYTE
      raise "Expected data to begin with a magic byte, got `#{magic_byte.inspect}`"
    end

    # The schema id is a 4-byte big-endian integer.
    schema_id = stream.read(4).unpack("N").first

    # For now, we're only going to support a single message per schema. See
    # https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html#wire-format
    read_int(stream)

    schema = @registry.fetch(schema_id)
    encoded = stream.read
    decode_protobuf(schema, encoded)
  rescue Excon::Error::NotFound
    raise SchemaNotFoundError.new("Schema with id: #{schema_id} is not found on registry")
  end

  private

  # Write an int with zig-zag encoding. Copied from Avro.
  def write_int(stream, n)
    n = (n << 1) ^ (n >> 63)
    while (n & ~0x7F) != 0
      stream.write(((n & 0x7f) | 0x80).chr)
      n >>= 7
    end
    stream.write(n.chr)
  end

  # Read an int with zig-zag encoding. Copied from Avro.
  def read_int(stream)
    b = stream.readbyte
    n = b & 0x7F
    shift = 7
    while (b & 0x80) != 0
      b = stream.readbyte
      n |= (b & 0x7F) << shift
      shift += 7
    end
    (n >> 1) ^ -(n & 1)
  end

  def decode_protobuf(schema, encoded)
    # get the package
    package = schema.match(/package (\S+);/)[1]
    # get the first message in the protobuf text
    # TODO - get the correct message based on schema index
    message_name = schema.match(/message (\w+) {/)[1]
    # look up the descriptor
    full_name = "#{package}.#{message_name}"
    descriptor = Google::Protobuf::DescriptorPool.generated_pool.lookup(full_name)
    unless descriptor
      raise "Could not find schema for #{full_name}. Make sure the corresponding .proto file has been compiled and loaded."
    end
    descriptor.msgclass.decode(encoded)
  end

  def register_schema(file_descriptor, subject: nil)
    subject ||= file_descriptor.name
    return if @registry.registered?(file_descriptor.name, subject)

    # register dependencies first
    dependencies = file_descriptor.to_proto.dependency.to_a.reject { |d| d.start_with?('google/protobuf/') }
    versions = dependencies.map do |dependency|
      dependency_descriptor = @all_schemas[dependency]
      result = register_schema(dependency_descriptor, subject: dependency_descriptor.name)
      @registry.fetch_version(result, dependency_descriptor.name)
    end

    @registry.register(subject,
                       schema_text(file_descriptor),
                       references: dependencies.map.with_index do |dependency, i|
                         {
                           name: dependency,
                           subject: dependency,
                           version: versions[i]
                         }
                       end
    )
  end

  def schema_text(file_descriptor)
    filename = "#{@path}/#{file_descriptor.name}"
    File.exist?(filename) ? File.read(filename) : ""
  end

  def load_schemas!
    all_messages = ObjectSpace.each_object(Class).select do |o|
      o < Google::Protobuf.const_get(:AbstractMessage)
    end.to_a
    all_messages.each do |m|
      file_desc = m.descriptor.file_descriptor
      file_path = file_desc.name
      next if file_path.start_with?('google/protobuf/') # skip built-in protos

      @all_schemas[file_path] = file_desc
    end
  end

end
