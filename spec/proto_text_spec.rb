RSpec.describe ProtoTurf::ProtoText do
  it "should output as expected" do
    output = described_class.output(Everything::V1::TestAllTypes.descriptor.file_descriptor.to_proto)

    expected = File.read("#{__dir__}/schemas/everything/everything.proto")
    expect(output).to eq(expected)
  end
end
