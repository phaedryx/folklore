module FolkloreMcp
  # Shapes a `read` response: raw content by default, or the requested
  # metadata fields in a fixed order, as text lines or a JSON object.
  class ReadFormatter
    METADATA_FIELDS = %i[
      name path content_type status owner tags created_at updated_at
      backlinks created_by updated_by verified_by version
    ].freeze

    def self.call(asset, requested:, format: "text")
      new(asset, requested:, format:).call
    end

    def initialize(asset, requested:, format:)
      @asset = asset
      @requested = Array(requested).map(&:to_sym)
      @format = format.to_s
    end

    def call
      json? ? json_payload : text_payload
    end

    private

    def json?
      @format == "json"
    end

    def data
      @data ||= AssetSerializer.call(@asset)
    end

    def backlinks
      @backlinks ||= Links::Backlinks.query(asset: @asset).map do |source|
        { slug: source.slug, location: source.location, name: source.name }
      end
    end

    def json_payload
      return data if @requested.empty?

      payload = { slug: data[:slug] }
      METADATA_FIELDS.select { |field| @requested.include?(field) }.each do |field|
        payload[field] = json_field_value(field)
      end
      payload[:content] = data[:content] if @requested.include?(:content)
      payload
    end

    def text_payload
      return @asset.content.to_s if @requested.empty?

      header = METADATA_FIELDS.select { |field| @requested.include?(field) }
                              .map { |field| text_field_line(field) }

      segments = []
      segments << header.join("\n") if header.any?
      segments << @asset.content.to_s if @requested.include?(:content)
      segments.join("\n---\n")
    end

    def json_field_value(field)
      case field
      when :owner then data[:owner_handle]
      when :tags then Array(data[:tags])
      when :backlinks then backlinks
      else data[field]
      end
    end

    def text_field_line(field)
      case field
      when :backlinks
        [ "backlinks:", *backlinks.map { |link| "#{link[:slug]}  #{link[:location]}" } ].join("\n")
      when :created_by, :updated_by, :verified_by
        "#{field}: #{actor_text(data[field])}"
      else
        "#{field}: #{json_field_value(field).then { |v| v.is_a?(Array) ? v.join(', ') : v }}"
      end
    end

    def actor_text(actor)
      actor ? "#{actor[:handle]}/#{actor[:agent]}" : ""
    end
  end
end
