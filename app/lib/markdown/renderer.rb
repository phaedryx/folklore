require "commonmarker"
require "rouge"

module Markdown
  # Turns an asset's content into HTML for the show page. Markdown is
  # rendered by commonmarker with fenced code highlighted by Rouge and
  # `[[slug]]` wikilinks rewritten to links on the target's current name;
  # recognised code extensions are highlighted whole; anything else is
  # escaped plain text. Markdown output is sanitised to a fixed tag list.
  class Renderer
    Rendered = Data.define(:html, :mode)

    WIKILINK = Markdown::Wikilinks::PATTERN
    ENCODED_WIKILINK = /%5B%5B(#{Asset::SLUG_PATTERN})(?:%7C([^\]\n|]+))?%5D%5D/i

    ALLOWED_TAGS = %w[h1 h2 h3 h4 h5 h6 p br hr strong em del s ul ol li a code pre blockquote
                      table thead tbody tr th td img input span div sup sub].freeze
    ALLOWED_ATTRIBUTES = %w[href title alt src type checked disabled class id].freeze

    CODE_LEXERS = {
      "rb" => "ruby", "ruby" => "ruby", "py" => "python", "js" => "javascript", "mjs" => "javascript",
      "ts" => "typescript", "tsx" => "tsx", "jsx" => "jsx", "go" => "go", "rs" => "rust", "java" => "java",
      "kt" => "kotlin", "c" => "c", "h" => "c", "cpp" => "cpp", "hpp" => "cpp", "cs" => "csharp",
      "swift" => "swift", "php" => "php", "sh" => "shell", "bash" => "shell", "zsh" => "shell",
      "fish" => "shell", "sql" => "sql", "json" => "json", "yml" => "yaml", "yaml" => "yaml",
      "toml" => "toml", "xml" => "xml", "html" => "html", "htm" => "html", "erb" => "erb", "css" => "css",
      "scss" => "scss", "lua" => "lua", "r" => "r", "ex" => "elixir", "exs" => "elixir", "elm" => "elm",
      "hs" => "haskell", "clj" => "clojure", "scala" => "scala", "dockerfile" => "docker"
    }.freeze

    # asset_url turns a resolved Asset into the href a wikilink points at;
    # routing is the caller's, not this class's.
    def self.call(content, content_type:, name:, asset_url:)
      new(content, content_type:, name:, asset_url:).call
    end

    def initialize(content, content_type:, name:, asset_url:)
      @content = content.to_s
      @content_type = content_type.to_s
      @name = name.to_s
      @asset_url = asset_url
      @resolved = {}
    end

    def call
      if markdown?
        Rendered.new(html: markdown_html, mode: :markdown)
      elsif (lexer = code_lexer)
        Rendered.new(html: highlight(lexer, @content).html_safe, mode: :code)
      else
        Rendered.new(html: ERB::Util.html_escape(@content), mode: :plain)
      end
    end

    private

    def markdown?
      %w[md markdown].include?(extension) || @content_type == "text/markdown"
    end

    def code_lexer
      key = @name.downcase == "dockerfile" ? "dockerfile" : extension
      CODE_LEXERS[key]&.then { |lang| Rouge::Lexer.find(lang) }
    end

    def extension
      @extension ||= File.extname(@name).delete_prefix(".").downcase
    end

    def markdown_html
      html = Commonmarker.to_html(
        @content,
        options: {
          extension: { table: true, strikethrough: true, autolink: true, tasklist: true, footnotes: true, header_ids: nil },
          render: { unsafe: false }
        },
        plugins: { syntax_highlighter: nil }
      )
      doc = Nokogiri::HTML5.fragment(html)
      highlight_code_blocks!(doc)
      expand_wikilinks!(doc)
      sanitize(doc.to_html)
    end

    def sanitize(html)
      Rails::HTML5::SafeListSanitizer.new.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).html_safe
    end

    def highlight(lexer, code)
      Rouge::Formatters::HTML.new.format(lexer.lex(code))
    end

    def highlight_code_blocks!(doc)
      doc.css("pre > code").each do |code|
        pre = code.parent
        lang = pre["lang"].presence || code["class"].to_s[/language-(\S+)/, 1]
        lexer = (lang && Rouge::Lexer.find(lang)) || Rouge::Lexers::PlainText
        pre.replace(%(<div class="highlight my-3 rounded"><pre><code>#{highlight(lexer, code.text)}</code></pre></div>))
      end
    end

    def expand_wikilinks!(doc)
      doc.traverse do |node|
        next unless node.text? && node.content.include?("[[") && !inside_code?(node)

        expand_text_node!(node)
      end
      doc.css("a[href], img[src]").each do |el|
        attr = el.name == "a" ? "href" : "src"
        value = el[attr]
        el[attr] = expand_in_attribute(value) if value && (value.include?("[[") || value.include?("%5B%5B"))
      end
    end

    def inside_code?(node)
      node.ancestors.any? { |a| %w[code pre].include?(a.name) }
    end

    def expand_text_node!(node)
      text = node.content
      pieces = []
      pos = 0
      text.scan(WIKILINK) do
        md = Regexp.last_match
        pieces << ERB::Util.html_escape(text[pos...md.begin(0)])
        pieces << link_html(md[0], md[1], md[2])
        pos = md.end(0)
      end
      return if pos.zero?

      pieces << ERB::Util.html_escape(text[pos..])
      node.replace(Nokogiri::HTML5.fragment(pieces.join))
    end

    def link_html(literal, slug, label)
      asset = resolve(slug)
      return ERB::Util.html_escape(literal) unless asset

      %(<a href="#{ERB::Util.html_escape(@asset_url.call(asset))}">#{ERB::Util.html_escape(label.presence || asset.name)}</a>)
    end

    def expand_in_attribute(value)
      value.gsub(Regexp.union(WIKILINK, ENCODED_WIKILINK)) do
        asset = resolve(Regexp.last_match(1) || Regexp.last_match(3))
        asset ? @asset_url.call(asset) : Regexp.last_match(0)
      end
    end

    def resolve(slug)
      return @resolved[slug] if @resolved.key?(slug)

      @resolved[slug] = Asset.live.find_by(slug:)
    end
  end
end
