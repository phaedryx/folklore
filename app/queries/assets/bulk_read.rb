module Assets
  # Many assets in one call, each named by a slug or a location, under a byte
  # budget for content. A ref that fails keeps its error in place, never fatal.
  class BulkRead
    DEFAULT_MAX_BYTES = 100_000
    MAX_BYTES = 1_000_000
    MAX_REFS = 50

    InvalidArgumentError = Class.new(Assets::Error)

    Result = Data.define(:items, :bytes_returned, :truncated)
    Item = Data.define(:ref, :asset, :error, :content_omitted)

    def self.query(refs:, max_bytes: DEFAULT_MAX_BYTES, include_content: true, actor: nil)
      new(refs:, max_bytes:, include_content:, actor:).query
    end

    # A location always has a "/" and a slug never does.
    def self.read_one(ref, actor: nil)
      ref.to_s.include?("/") ? ReadByPath.query(location: ref, actor:) : Read.query(slug: ref, actor:)
    end

    def initialize(refs:, max_bytes:, include_content:, actor:)
      @refs = Array(refs)
      @max_bytes = max_bytes.to_i.positive? ? [ max_bytes.to_i, MAX_BYTES ].min : DEFAULT_MAX_BYTES
      @include_content = include_content
      @actor = actor
    end

    def query
      raise InvalidArgumentError, "read takes at least one ref" if @refs.empty?
      raise InvalidArgumentError, "read takes at most #{MAX_REFS} refs, got #{@refs.size}" if @refs.size > MAX_REFS

      bytes = 0
      truncated = false

      items = @refs.map do |ref|
        item = read_item(ref)
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

    def read_item(ref)
      Item.new(ref:, asset: self.class.read_one(ref, actor: @actor), error: nil, content_omitted: false)
    rescue Assets::NotFoundError, Assets::InvalidLocationError => e
      Item.new(ref:, asset: nil, error: e, content_omitted: false)
    end
  end
end
