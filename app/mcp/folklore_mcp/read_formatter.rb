module FolkloreMcp
  # Shapes one asset for `read`: the full serialized asset when nothing is
  # named, otherwise its slug and the named fields in a fixed order, with
  # content last.
  class ReadFormatter
    FIELDS = %w[
      content name path content_type kind status owner tags created_at updated_at
      backlinks created_by updated_by verified_by version
    ].freeze
    METADATA_FIELDS = (FIELDS - %w[content]).map(&:to_sym).freeze

    def self.call(asset, include:)
      new(asset, include:).call
    end

    def initialize(asset, include:)
      @asset = asset
      @include = include&.map(&:to_sym)
    end

    def call
      return data if @include.nil?

      payload = { slug: data[:slug] }
      METADATA_FIELDS.select { |field| @include.include?(field) }.each { |field| payload[field] = value(field) }
      payload[:content] = data[:content] if @include.include?(:content)
      payload
    end

    private

    def data
      @data ||= ::Assets::Serializer.call(@asset)
    end

    def value(field)
      case field
      when :owner then data[:owner_handle]
      when :backlinks then backlinks
      else data[field]
      end
    end

    def backlinks
      Links::Backlinks.query(asset: @asset).map do |source|
        { slug: source.slug, location: source.location, name: source.name }
      end
    end
  end
end
