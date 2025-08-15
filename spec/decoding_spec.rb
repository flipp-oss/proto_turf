RSpec.describe "encoding" do
  let(:proto_turf) do
    ProtoTurf.new(
      registry_url: "http://localhost:8081",
      schema_paths: ["spec/schemas"]
    )
  end

  it "should decode a simple message" do
    schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    stub = stub_request(:get, "http://localhost:8081/schemas/ids/15")
      .to_return_json(body: {schema: schema})
    msg = Simple::V1::SimpleMessage.new(name: "my name")
    encoded = "\u0000\u0000\u0000\u0000\u000F\u0000" + msg.to_proto
    expect(proto_turf.decode(encoded)).to eq(msg)

    # if we do it again we should not see any more requests
    expect(proto_turf.decode(encoded)).to eq(msg)

    expect(stub).to have_been_requested.once
  end

  it "should decode a complex message" do
    schema = File.read("#{__dir__}/schemas/referenced/referer.proto")
    stub = stub_request(:get, "http://localhost:8081/schemas/ids/20")
      .to_return_json(body: {schema: schema})
    msg = Referenced::V1::MessageB::MessageBA.new(
      simple: Simple::V1::SimpleMessage.new(name: "my name")
    )
    encoded = "\u0000\u0000\u0000\u0000\u0014\u0004\u0002\u0000" + msg.to_proto
    expect(proto_turf.decode(encoded)).to eq(msg)

    # if we do it again we should not see any more requests
    expect(proto_turf.decode(encoded)).to eq(msg)
    expect(stub).to have_been_requested.once
  end
end
