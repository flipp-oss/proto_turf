# frozen_string_literal: true

require 'proto_turf/output/json_schema'

RSpec.describe ProtoTurf::Output::JsonSchema do
  it 'should output as expected' do
    output = described_class.output(Everything::V1::TestAllTypes.descriptor.to_proto)

    expected = File.read("#{__dir__}/schemas/everything/everything.json")
    expect("#{output}\n").to eq(expected)
  end
end
