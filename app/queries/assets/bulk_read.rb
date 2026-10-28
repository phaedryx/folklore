module Assets
  # Many assets in one call, keyed by slug or location, under a byte budget
  # for content. A key that fails is reported in place, never fatal.
  class BulkRead
    DEFAULT_MAX_BYTES = 100_000

    Result = Data.define(:items, :bytes_returned, :truncated)
    Item = Data.define(:key, :asset, :error, :content_omitted)

    def self.query(slugs: [], locations: [], max_bytes: DEFAULT_MAX_BYTES, include_content: true, actor: nil)
      new(slugs:, locations:, max_bytes:, include_content:, actor:).query
    end

    def initialize(slugs:, locations:, max_bytes:, include_content:, actor:)
      @slugs = Array(slugs)
      @locations = Array(locations)
      @max_bytes = max_bytes.to_i.positive? ? max_bytes.to_i : DEFAULT_MAX_BYTES
      @include_content = include_content
      @actor = actor
    end

    def query
      bytes = 0
      truncated = false

      items = keys.map do |type, value|
        item = read_one(type, value)
        next item unless item.asset && @include_content

        size = item.asset.content.to_s.bytesize
        if truncated || bytes + size > @max_bytes
          truncated = true
          item.with(content_omitted: true)
        else
          bytes += size
          item
        end
      end

      Result.new(items:, bytes_returned: bytes, truncated:)
    end

    private

    def keys
      @slugs.map { |s| [ :slug, s ] } + @locations.map { |l| [ :location, l ] }
    end

    def read_one(type, value)
      asset = type == :slug ? Assets::Read.query(slug: value, actor: @actor)
                            : Assets::ReadByPath.query(location: value, actor: @actor)
      Item.new(key: value, asset:, error: nil, content_omitted: false)
    rescue Assets::NotFoundError
      Item.new(key: value, asset: nil, error: "not_found", content_omitted: false)
    rescue Assets::InvalidLocationError => e
      Item.new(key: value, asset: nil, error: e.message, content_omitted: false)
    end
  end
end
