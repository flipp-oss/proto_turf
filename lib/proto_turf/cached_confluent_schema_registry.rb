class ProtoTurf::CachedConfluentSchemaRegistry

  # @param upstream [ProtoTurf::ConfluentSchemaRegistry]
  def initialize(upstream)
    @upstream = upstream
    @schemas_by_id = {}
    @ids_by_schema = {}
    @versions_by_subject_and_id = {}
  end

  # Delegate the following methods to the upstream
  %i(subject_versions schema_subject_versions).each do |name|
    define_method(name) do |*args|
      instance_variable_get(:@upstream).send(name, *args)
    end
  end

  # @param id [Integer] the schema ID to fetch
  # @return [String] the schema string stored in the registry for the given id
  def fetch(id)
    @schemas_by_id[id] ||= @upstream.fetch(id)
  end

  # @param id [Integer] the schema ID to fetch
  # @param subject [String] the subject to fetch the version for
  # @return [Integer, nil] the version of the schema for the given subject and id, or nil if not found
  def fetch_version(id, subject)
    key = [subject, id]
    return @versions_by_subject_and_id[key] if @versions_by_subject_and_id[key]

    results = @upstream.schema_subject_versions(id)
    @versions_by_subject_and_id[key] = results&.find { |r| r['subject'] == subject }&.dig('version')
  end

  # @param subject [String] the subject to check
  # @param schema [String] the schema text to check
  # @return [Boolean] true if we know the schema has been registered for that subject.
  def registered?(subject, schema)
    @ids_by_schema[[subject, schema]].present?
  end

  # @param subject [String] the subject to register the schema under
  # @param schema [String] the schema text to register
  # @param references [Array<Hash>] optional references to other schemas
  def register(subject, schema, references: [])
    key = [subject, schema]

    @ids_by_schema[key] ||= @upstream.register(subject, schema, references: references)
  end

end
