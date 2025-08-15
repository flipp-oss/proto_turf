# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("gen", __dir__))
Dir["#{__dir__}/gen/**/*.rb"].each { |file| require file }
require "proto_turf"
require "webmock/rspec"

RSpec.configure do |config|
  config.full_backtrace = true

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
