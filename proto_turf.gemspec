lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "proto_turf/version"

Gem::Specification.new do |spec|
  spec.name = "proto_turf"
  spec.version = ProtoTurf::VERSION
  spec.authors = ["Daniel Orner"]
  spec.email = ["daniel.orner@flipp.com"]
  spec.summary = "Support for Protobuf files in Confluent Schema Registry"
  spec.homepage = "https://github.com/flipp-oss/proto_turf"
  spec.license = "MIT"

  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = `git ls-files -z`.split("\x0")
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "google-protobuf"
  spec.add_dependency "excon"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.2"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "standardrb"
end
