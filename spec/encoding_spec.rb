RSpec.describe "encoding" do
  let(:proto_turf) do
    ProtoTurf.new(
      registry_url: "http://localhost:8081"
    )
  end

  it "should encode a simple message" do
    schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    stub = stub_request(:post, "http://localhost:8081/subjects/simple/versions")
      .with(body: {"schemaType" => "PROTOBUF",
                   "references" => [],
                   "schema" => schema}).to_return_json(body: {id: 15})
    msg = Simple::V1::SimpleMessage.new(name: "my name")
    encoded = proto_turf.encode(msg, subject: "simple")
    expect(encoded).to eq("\u0000\u0000\u0000\u0000\u000F\u0000" + msg.to_proto)

    # if we do it again we should not see any more requests
    encoded2 = proto_turf.encode(msg, subject: "simple")
    expect(encoded2).to eq(encoded)

    expect(stub).to have_been_requested.once
  end

  it "should encode a complex message" do
    schema = File.read("#{__dir__}/schemas/referenced/referer.proto")
    dep_schema = File.read("#{__dir__}/schemas/simple/simple.proto")
    dep_stub = stub_request(:post, "http://localhost:8081/subjects/simple%2Fsimple.proto/versions")
      .with(body: {"schemaType" => "PROTOBUF",
                   "references" => [],
                   "schema" => dep_schema}).to_return_json(body: {id: 15})
    version_stub = stub_request(:get, "http://localhost:8081/schemas/ids/15/versions")
      .to_return_json(body: [{version: 1, subject: "simple/simple.proto"}])
    stub = stub_request(:post, "http://localhost:8081/subjects/referenced/versions")
      .with(body: {"schemaType" => "PROTOBUF",
                   "references" => [
                     {
                       name: "simple/simple.proto",
                       subject: "simple/simple.proto",
                       version: 1
                     }
                   ],
                   "schema" => schema}).to_return_json(body: {id: 20})
    msg = Referenced::V1::MessageB::MessageBA.new(
      simple: Simple::V1::SimpleMessage.new(name: "my name")
    )
    encoded = proto_turf.encode(msg, subject: "referenced")
    expect(encoded).to eq("\u0000\u0000\u0000\u0000\u0014\u0004\u0002\u0000" + msg.to_proto)

    # if we do it again we should not see any more requests
    encoded2 = proto_turf.encode(msg, subject: "referenced")
    expect(encoded2).to eq(encoded)
    expect(stub).to have_been_requested.once
    expect(dep_stub).to have_been_requested.once
    expect(version_stub).to have_been_requested.once
  end
end
