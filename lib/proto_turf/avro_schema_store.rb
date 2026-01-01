# frozen_string_literal: true

require "avro"

class ProtoTurf
  class AvroSchemaStore
    def initialize(path: nil)
      @path = path or raise "Please specify a schema path"
      @schemas = {}
      @schema_text = {}
      @mutex = Mutex.new
    end

    attr_accessor :schemas

    def find_text(name)
      @schema_text[name]
    end

    # Resolves and returns a schema.
    #
    # schema_name - The String name of the schema to resolve.
    #
    # Returns an Avro::Schema.
    def find(name)
      # Optimistic non-blocking read from @schemas
      # No sense to lock the resource when all the schemas already loaded
      return @schemas[name] if @schemas.key?(name)

      # Pessimistic blocking write to @schemas
      @mutex.synchronize do
        # Still need to check is the schema already loaded
        return @schemas[name] if @schemas.key?(name)

        load_schema!(name, @schemas.dup)
      end
    end

    # Loads all schema definition files in the `schemas_dir`.
    def load_schemas!
      pattern = [@path, "**", "*.avsc"].join("/")

      Dir.glob(pattern) do |schema_path|
        # Remove the path prefix.
        schema_path.sub!(/^\/?#{@path}\//, "")

        # Replace `/` with `.` and chop off the file extension.
        schema_name = File.basename(schema_path.tr("/", "."), ".avsc")

        # Load and cache the schema.
        find(schema_name)
      end
    end

    # @param schema_hash [Hash]
    def add_schema(schema_hash)
      name = schema_hash["name"]
      namespace = schema_hash["namespace"]
      full_name = Avro::Name.make_fullname(name, namespace)
      return if @schemas.key?(full_name)

      # We pass in copy of @schemas which Avro can freely modify
      # and register the sub-schema. It doesn't matter because
      # we will discard it.
      schema = Avro::Schema.real_parse(schema_hash, @schemas.dup)
      @schemas[full_name] = schema
      @schema_text[full_name] = JSON.pretty_generate(schema_hash)

      schema
    end

    protected

    # Loads single schema
    # Such method is not thread-safe, do not call it of from mutex synchronization routine
    def load_schema!(fullname, local_schemas_cache = {})
      schema_path = build_schema_path(fullname)
      schema_text = File.read(schema_path)
      schema_json = JSON.parse(schema_text)

      schema = Avro::Schema.real_parse(schema_json, local_schemas_cache)

      # Don't cache the parsed schema until after its fullname is validated
      if schema.respond_to?(:fullname) && schema.fullname != fullname
        raise AvroTurf::SchemaError, "expected schema `#{schema_path}' to define type `#{fullname}'"
      end

      # Cache only this new top-level schema by its fullname. It's critical
      # not to make every sub-schema resolvable at the top level here because
      # multiple different avsc files may define the same sub-schema, and
      # if we share the @schemas cache across all parsing contexts, the Avro
      # gem will raise an Avro::SchemaParseError when parsing another avsc
      # file that contains a subschema with the same fullname as one
      # encountered previously in a different file:
      # <Avro::SchemaParseError: The name "foo.bar" is already in use.>
      # Essentially, the only schemas that should be resolvable in @schemas
      # are those that have their own .avsc files on disk.
      @schemas[fullname] = schema
      @schema_text[fullname] = schema_text

      schema
    rescue ::Avro::UnknownSchemaError => e
      # Try to first resolve a referenced schema from disk.
      # If this is successful, the Avro gem will have mutated the
      # local_schemas_cache, adding all the new schemas it found.
      load_schema!(::Avro::Name.make_fullname(e.type_name, e.default_namespace), local_schemas_cache)

      # Attempt to re-parse the original schema now that the dependency
      # has been resolved and use the now-updated local_schemas_cache to
      # pick up where we left off.
      local_schemas_cache.delete(fullname)
      # Ensure all sub-schemas are cleaned up to avoid conflicts when re-parsing
      # schema.
      local_schemas_cache.each_key do |schema_name|
        local_schemas_cache.delete(schema_name) unless File.exist?(build_schema_path(schema_name))
      end
      load_schema!(fullname, @schemas.dup)
    rescue Errno::ENOENT, Errno::ENAMETOOLONG
      raise "could not find Avro schema at `#{schema_path}'"
    end

    def build_schema_path(fullname)
      *namespace, schema_name = fullname.split(".")
      File.join(@path, *namespace, "#{schema_name}.avsc")
    end
  end
end
