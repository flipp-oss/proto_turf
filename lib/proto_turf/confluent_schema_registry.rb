require 'excon'

class ProtoTurf
  class ConfluentSchemaRegistry

    CONTENT_TYPE = "application/vnd.schemaregistry.v1+json".freeze

    def initialize(
      url,
      schema_context: nil,
      logger: Logger.new($stdout),
      proxy: nil,
      user: nil,
      password: nil,
      ssl_ca_file: nil,
      client_cert: nil,
      client_key: nil,
      client_key_pass: nil,
      client_cert_data: nil,
      client_key_data: nil,
      path_prefix: nil,
      connect_timeout: nil,
      resolv_resolver: nil,
      retry_limit: nil
    )
      @path_prefix = path_prefix
      @schema_context_prefix = schema_context.nil? ? '' : ":.#{schema_context}:"
      @schema_context_options = schema_context.nil? ? {} : {query: {subject: @schema_context_prefix}}
      @logger = logger
      headers = Excon.defaults[:headers].merge(
        "Content-Type" => CONTENT_TYPE
      )
      params = {
        headers: headers,
        user: user,
        password: password,
        proxy: proxy,
        ssl_ca_file: ssl_ca_file,
        client_cert: client_cert,
        client_key: client_key,
        client_key_pass: client_key_pass,
        client_cert_data: client_cert_data,
        client_key_data: client_key_data,
        resolv_resolver: resolv_resolver,
        connect_timeout: connect_timeout,
        retry_limit: retry_limit
      }
      # Remove nil params to allow Excon to use its default values
      params.reject! { |_, v| v.nil? }
      @connection = Excon.new(
        url,
        params
      )
    end

    # @param id [Integer] the schema ID to fetch
    # @return [String] the schema string stored in the registry for the given id
    def fetch(id)
      @logger.info "Fetching schema with id #{id}"
      data = get("/schemas/ids/#{id}", idempotent: true, **@schema_context_options, )
      data.fetch("schema")
    end

    # @param schema_id [Integer] the schema ID to fetch versions for
    # @return [Array<Hash>] an array of versions for the given schema ID
    def schema_subject_versions(schema_id)
      get("/schemas/ids/#{schema_id}/versions", idempotent: true, **@schema_context_options)
    end

    # @param subject [String] the subject to check
    # @param schema [String] the schema text to check
    # @param references [Array<Hash>] optional references to other schemas
    # @return [Integer] the ID of the registered schema
    def register(subject, schema, references: [])
      data = post("/subjects/#{@schema_context_prefix}#{CGI.escapeURIComponent(subject)}/versions",
                  body: { schemaType: 'PROTOBUF',
                          references: references,
                          schema: schema.to_s }.to_json)

      id = data.fetch("id")

      @logger.info "Registered schema for subject `#{@schema_context_prefix}#{subject}`; id = #{id}"

      id
    end

    # @param subject [String]
    # @return [Array<Hash>] an array of versions for the given subject
    def subject_versions(subject)
      get("/subjects/#{@schema_context_prefix}#{CGI.escapeURIComponent(subject)}/versions", idempotent: true)
    end

    private

    def get(path, **options)
      request(path, method: :get, **options)
    end

    def put(path, **options)
      request(path, method: :put, **options)
    end

    def post(path, **options)
      request(path, method: :post, **options)
    end

    def request(path, **options)
      options = { expects: 200 }.merge!(options)
      path = File.join(@path_prefix, path) unless @path_prefix.nil?
      response = @connection.request(path: path, **options)
      JSON.parse(response.body)
    rescue Excon::Error => e
      @logger.error("Error while requesting #{path}: #{e.response.body}")
      raise
    end

  end
end
