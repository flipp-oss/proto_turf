# proto_turf

`proto_turf` is a library to interact with the Confluent Schema Registry using Google Protobuf. It is inspired by and based off of [avro_turf](https://github.com/dasch/avro_turf).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'proto_turf'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install proto_turf

## Usage

ProtoTurf interacts with the Confluent Schema Registry, and caches all results. When you first encode a message, it will register the message and all dependencies with the Schema Registry. When decoding, it will look up the schema in the Schema Registry and use the associated local generated code to decode the message.

Example usage:

```ruby
require 'proto_turf'

proto_turf = ProtoTurf.new(registry_url: 'http://localhost:8081', schema_paths: ['path/to/protos'])
message = MyProto::MyMessage.new(field1: 'value1', field2: 42)
encoded = proto_turf.encode(message, subject: 'my-subject')

# Decoding

decoded_proto_message = proto_turf.decode(encoded_string)
```

If you're using [buf](https://buf.build/) to manage your Protobuf definitions, you should run `buf export` before using `proto_turf` to ensure that all the dependencies are available as `.proto` files in your project. The actual proto text is needed when registering the schema with the Schema Registry.

Because `buf export` overwrites/deletes existing files, you should run it into a different directory and provide both as `schema_paths` to the `ProtoTurf` constructor.

## Notes about usage

* When decoding, this library does *not* attempt to fully parse the Proto definition stored on the schema registry and generate dynamic classes. Instead, it simply parses out the package and message and assumes that the reader has the message available in the descriptor pool. Any compatibility issues should be detected through normal means, i.e. just by instantiating the message and seeing if any errors are raised.

### Regenerating test protos
Run the following to regenerate:

```sh
protoc -I spec/schemas --ruby_out=spec/gen --ruby_opt=paths=source_relative spec/schemas/**/*.proto
```