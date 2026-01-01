# frozen_string_literal: true

RSpec.describe 'encoding' do
  let(:proto_turf) do
    ProtoTurf.new(
      registry_url: 'http://localhost:8081'
    )
  end

  it 'should encode a simple message' do
    schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    stub = stub_request(:post, 'http://localhost:8081/subjects/simple/versions')
           .with(body: { 'schemaType' => 'PROTOBUF',
                         'references' => [],
                         'schema' => schema }).to_return_json(body: { id: 15 })
    msg = Simple::V1::SimpleMessage.new(name: 'my name')
    encoded = proto_turf.encode(msg, subject: 'simple')
    expect(encoded).to eq("\u0000\u0000\u0000\u0000\u000F\u0000#{msg.to_proto}")

    # if we do it again we should not see any more requests
    encoded2 = proto_turf.encode(msg, subject: 'simple')
    expect(encoded2).to eq(encoded)

    expect(stub).to have_been_requested.once
  end

  it 'should encode a complex message' do
    schema = File.read("#{__dir__}/schemas/referenced/referer.proto")
    dep_schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    dep_stub = stub_request(:post, 'http://localhost:8081/subjects/simple%2Fsimple.proto/versions')
               .with(body: { 'schemaType' => 'PROTOBUF',
                             'references' => [],
                             'schema' => dep_schema }).to_return_json(body: { id: 15 })
    version_stub = stub_request(:get, 'http://localhost:8081/schemas/ids/15/versions')
                   .to_return_json(body: [{ version: 1, subject: 'simple/simple.proto' }])
    stub = stub_request(:post, 'http://localhost:8081/subjects/referenced/versions')
           .with(body: { 'schemaType' => 'PROTOBUF',
                         'references' => [
                           {
                             name: 'simple/simple.proto',
                             subject: 'simple/simple.proto',
                             version: 1
                           }
                         ],
                         'schema' => schema }).to_return_json(body: { id: 20 })
    msg = Referenced::V1::MessageB::MessageBA.new(
      simple: Simple::V1::SimpleMessage.new(name: 'my name')
    )
    encoded = proto_turf.encode(msg, subject: 'referenced')
    expect(encoded).to eq("\u0000\u0000\u0000\u0000\u0014\u0004\u0002\u0000#{msg.to_proto}")

    # if we do it again we should not see any more requests
    encoded2 = proto_turf.encode(msg, subject: 'referenced')
    expect(encoded2).to eq(encoded)
    expect(stub).to have_been_requested.once
    expect(dep_stub).to have_been_requested.once
    expect(version_stub).to have_been_requested.once
  end

  describe 'with JSON' do
    let(:proto_turf) do
      ProtoTurf.new(
        registry_url: 'http://localhost:8081',
        schema_type: ProtoTurf::Schema::ProtoJsonSchema
      )
    end

    it 'should encode a simple message' do
      schema = File.read("#{__dir__}/schemas/simple/simple.json").strip
      stub = stub_request(:post, 'http://localhost:8081/subjects/simple/versions')
             .with(body: { 'schemaType' => 'JSON',
                           'references' => [],
                           'schema' => schema }).to_return_json(body: { id: 15 })
      msg = Simple::V1::SimpleMessage.new(name: 'my name')
      encoded = proto_turf.encode(msg, subject: 'simple')
      expect(encoded).to eq("\u0000\u0000\u0000\u0000\u000F{\"name\":\"my name\"}")

      # if we do it again we should not see any more requests
      encoded2 = proto_turf.encode(msg, subject: 'simple')
      expect(encoded2).to eq(encoded)

      expect(stub).to have_been_requested.once
    end

    it 'should encode a complex message' do
      schema = File.read("#{__dir__}/schemas/referenced/referenced.json").strip
      stub = stub_request(:post, 'http://localhost:8081/subjects/referenced/versions')
             .with(body: { 'schemaType' => 'JSON',
                           'references' => [],
                           'schema' => schema }).to_return_json(body: { id: 20 })
      msg = Referenced::V1::MessageB::MessageBA.new(
        simple: Simple::V1::SimpleMessage.new(name: 'my name')
      )
      encoded = proto_turf.encode(msg, subject: 'referenced')
      expect(encoded).to eq("\u0000\u0000\u0000\u0000\u0014{\"simple\":{\"name\":\"my name\"}}")

      # if we do it again we should not see any more requests
      encoded2 = proto_turf.encode(msg, subject: 'referenced')
      expect(encoded2).to eq(encoded)
      expect(stub).to have_been_requested.once
    end
  end

  describe 'with Avro' do
    let(:proto_turf) do
      ProtoTurf.avro_schema_path = "#{__dir__}/schemas"
      ProtoTurf.new(
        registry_url: 'http://localhost:8081',
        schema_type: ProtoTurf::Schema::Avro
      )
    end

    after do
      ProtoTurf.avro_schema_path = nil
    end

    it 'should encode a simple message' do
      schema = File.read("#{__dir__}/schemas/simple/v1/SimpleMessage.avsc")
      stub = stub_request(:post, 'http://localhost:8081/subjects/simple/versions')
             .with(body: { 'schemaType' => 'AVRO',
                           'references' => [],
                           'schema' => schema }).to_return_json(body: { id: 15 })
      msg = { 'name' => 'my name' }
      encoded = proto_turf.encode(msg, subject: 'simple', schema_name: 'simple.v1.SimpleMessage')
      # Avro encoding: magic byte (0x00) + schema id (4 bytes, big-endian) + Avro binary data
      # "my name" encoded as Avro string: length (0x0E = 14) + "my name" bytes
      expect(encoded).to eq("\u0000\u0000\u0000\u0000\u000F\u000Emy name")

      # if we do it again we should not see any more requests
      encoded2 = proto_turf.encode(msg, subject: 'simple', schema_name: 'simple.v1.SimpleMessage')
      expect(encoded2).to eq(encoded)

      expect(stub).to have_been_requested.once
    end

    it 'should encode a complex message with nested record' do
      schema = File.read("#{__dir__}/schemas/referenced/v1/MessageBA.avsc")
      stub = stub_request(:post, 'http://localhost:8081/subjects/referenced/versions')
             .with(body: { 'schemaType' => 'AVRO',
                           'references' => [],
                           'schema' => schema }).to_return_json(body: { id: 20 })
      msg = {
        'simple' => {
          'name' => 'my name'
        }
      }
      encoded = proto_turf.encode(msg, subject: 'referenced', schema_name: 'referenced.v1.MessageBA')
      # Avro encoding: magic byte + schema id + Avro binary for nested record
      expect(encoded).to eq("\u0000\u0000\u0000\u0000\u0014\u000Emy name")

      # if we do it again we should not see any more requests
      encoded2 = proto_turf.encode(msg, subject: 'referenced', schema_name: 'referenced.v1.MessageBA')
      expect(encoded2).to eq(encoded)
      expect(stub).to have_been_requested.once
    end

    it 'should handle multiple fields' do
      # Create a temporary schema file for testing
      multi_schema_path = "#{__dir__}/schemas/test/v1"
      FileUtils.mkdir_p(multi_schema_path)

      multi_schema = {
        'type' => 'record',
        'name' => 'MultiFieldMessage',
        'namespace' => 'test.v1',
        'fields' => [
          { 'name' => 'name', 'type' => 'string' },
          { 'name' => 'age', 'type' => 'int' }
        ]
      }
      schema_json = JSON.pretty_generate(multi_schema)
      File.write("#{multi_schema_path}/MultiFieldMessage.avsc", schema_json)

      stub = stub_request(:post, 'http://localhost:8081/subjects/multi/versions')
             .with(body: { 'schemaType' => 'AVRO',
                           'references' => [],
                           'schema' => schema_json }).to_return_json(body: { id: 25 })

      msg = { 'name' => 'Alice', 'age' => 30 }
      encoded = proto_turf.encode(msg, subject: 'multi', schema_name: 'test.v1.MultiFieldMessage')

      # Verify encoding starts with magic byte and schema id
      expect(encoded[0]).to eq("\u0000")
      expect(encoded[1..4].unpack1('N')).to eq(25)

      expect(stub).to have_been_requested.once

      # Clean up
      FileUtils.rm_rf("#{__dir__}/schemas/test")
    end

    it 'should validate schema before encoding' do
      schema = File.read("#{__dir__}/schemas/simple/v1/SimpleMessage.avsc")
      stub_request(:post, 'http://localhost:8081/subjects/simple/versions')
        .with(body: { 'schemaType' => 'AVRO',
                      'references' => [],
                      'schema' => schema }).to_return_json(body: { id: 15 })

      # Invalid message - missing required field
      msg = { 'invalid_field' => 'value' }

      expect do
        proto_turf.encode(msg, subject: 'simple', schema_name: 'simple.v1.SimpleMessage')
      end.to raise_error(Avro::SchemaValidator::ValidationError)
    end
  end

end
