# frozen_string_literal: true

RSpec.describe 'decoding' do
  let(:proto_turf) do
    ProtoTurf.new(
      registry_url: 'http://localhost:8081'
    )
  end

  it 'should decode a simple message' do
    schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    stub = stub_request(:get, 'http://localhost:8081/schemas/ids/15')
           .to_return_json(body: { schema: schema })
    msg = Simple::V1::SimpleMessage.new(name: 'my name')
    encoded = "\u0000\u0000\u0000\u0000\u000F\u0000#{msg.to_proto}"
    expect(proto_turf.decode(encoded)).to eq(msg)

    # if we do it again we should not see any more requests
    expect(proto_turf.decode(encoded)).to eq(msg)

    expect(stub).to have_been_requested.once
  end

  it 'should decode a complex message' do
    schema = File.read("#{__dir__}/schemas/referenced/referer.proto")
    stub = stub_request(:get, 'http://localhost:8081/schemas/ids/20')
           .to_return_json(body: { schema: schema })
    msg = Referenced::V1::MessageB::MessageBA.new(
      simple: Simple::V1::SimpleMessage.new(name: 'my name')
    )
    encoded = "\u0000\u0000\u0000\u0000\u0014\u0004\u0002\u0000#{msg.to_proto}"
    expect(proto_turf.decode(encoded)).to eq(msg)

    # if we do it again we should not see any more requests
    expect(proto_turf.decode(encoded)).to eq(msg)
    expect(stub).to have_been_requested.once
  end

  describe 'with JSON' do
    let(:proto_turf) do
      ProtoTurf.new(
        registry_url: 'http://localhost:8081',
        schema_type: ProtoTurf::Schema::ProtoJsonSchema
      )
    end

    it 'should decode a simple message' do
      schema = File.read("#{__dir__}/schemas/simple/simple.json")
      stub = stub_request(:get, 'http://localhost:8081/schemas/ids/15')
             .to_return_json(body: { schema: schema })
      encoded = "\u0000\u0000\u0000\u0000\u000F{\"name\":\"my name\"}"
      msg = { 'name' => 'my name' }
      expect(proto_turf.decode(encoded)).to eq(msg)

      # if we do it again we should not see any more requests
      expect(proto_turf.decode(encoded)).to eq(msg)

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

    it 'should decode a simple message' do
      schema = File.read("#{__dir__}/schemas/simple/v1/SimpleMessage.avsc")
      stub = stub_request(:get, 'http://localhost:8081/schemas/ids/15')
             .to_return_json(body: { schema: schema })

      # Avro-encoded data: "my name" as string (length 0x0E + bytes)
      encoded = "\u0000\u0000\u0000\u0000\u000F\u000Emy name"
      decoded = proto_turf.decode(encoded)

      expect(decoded).to eq({ 'name' => 'my name' })

      # if we do it again we should not see any more requests
      expect(proto_turf.decode(encoded)).to eq(decoded)

      expect(stub).to have_been_requested.once
    end

    it 'should decode a complex message with nested record' do
      schema = File.read("#{__dir__}/schemas/referenced/v1/MessageBA.avsc")
      stub = stub_request(:get, 'http://localhost:8081/schemas/ids/20')
             .to_return_json(body: { schema: schema })

      # Avro-encoded nested record
      encoded = "\u0000\u0000\u0000\u0000\u0014\u000Emy name"
      decoded = proto_turf.decode(encoded)

      expect(decoded).to eq({
                              'simple' => {
                                'name' => 'my name'
                              }
                            })

      # if we do it again we should not see any more requests
      expect(proto_turf.decode(encoded)).to eq(decoded)
      expect(stub).to have_been_requested.once
    end

    it 'should decode a message with multiple fields' do
      multi_schema = {
        'type' => 'record',
        'name' => 'MultiFieldMessage',
        'namespace' => 'test.v1',
        'fields' => [
          { 'name' => 'name', 'type' => 'string' },
          { 'name' => 'age', 'type' => 'int' }
        ]
      }
      schema_json = JSON.generate(multi_schema)

      stub = stub_request(:get, 'http://localhost:8081/schemas/ids/25')
             .to_return_json(body: { schema: schema_json })

      # Manually encode the message for testing
      # Alice = 0x0A (length 5*2) + "Alice" bytes
      # age 30 = zigzag encoded as 60 (0x3C)
      encoded = "\u0000\u0000\u0000\u0000\u0019\u000AAlice\u003C"
      decoded = proto_turf.decode(encoded)

      expect(decoded).to eq({ 'name' => 'Alice', 'age' => 30 })

      expect(stub).to have_been_requested.once
    end

    it 'should handle schema evolution with reader schema' do
      # Writer schema (what was used to encode) - has an additional field with default
      writer_schema = {
        'type' => 'record',
        'name' => 'SimpleMessage',
        'namespace' => 'simple.v1',
        'fields' => [
          { 'name' => 'name', 'type' => 'string' },
          { 'name' => 'age', 'type' => 'int', 'default' => 0 }
        ]
      }

      # Reader schema (what we have locally) - doesn't have the age field
      # This simulates reading old data with a newer schema or vice versa

      stub = stub_request(:get, 'http://localhost:8081/schemas/ids/15')
             .to_return_json(body: { schema: JSON.generate(writer_schema) })

      # Encoded with writer schema: "my name" (0x0E + bytes) + age 25 (zigzag encoded as 50 = 0x32)
      encoded = "\u0000\u0000\u0000\u0000\u000F\u000Emy name\u0032"
      decoded = proto_turf.decode(encoded)

      # Decoded value should only have 'name' from reader schema, age is ignored
      expect(decoded).to eq({ 'name' => 'my name' })
      expect(stub).to have_been_requested.once
    end

    it 'should raise error for invalid magic byte' do
      # Wrong magic byte (0x01 instead of 0x00)
      encoded = "\u0001\u0000\u0000\u0000\u000F\u000Emy name"

      expect do
        proto_turf.decode(encoded)
      end.to raise_error(/Expected data to begin with a magic byte/)
    end

    it 'should raise error for unknown schema id' do
      # Schema ID 999 is not stubbed, so decoding should fail
      encoded = "\u0000\u0000\u0000\u0003\u00E7\u000Emy name"

      expect do
        proto_turf.decode(encoded)
      end.to raise_error(/Schema|not found/i)
    end
  end
end
