require "json"

module Bundles
  # The v1 bundle format: a directory of asset files (YAML front matter, then
  # the content byte for byte), a JSON-lines file of versions per asset, and a
  # manifest. docs/bundle.md describes it for someone writing one by hand;
  # this module is the one place it is read and written.
  #
  # Dumping is canonical (fixed key order, every key present). Loading is
  # lenient: an absent optional key reads as null, so a bundle written by
  # another tool need not match this writer's layout exactly.
  module Format
    InvalidError = Class.new(StandardError)

    NAME = "folklore-bundle".freeze
    VERSION = 1
    MANIFEST = "manifest.json".freeze
    ASSETS_DIR = "assets".freeze
    ARCHIVED_DIR = "archived".freeze
    VERSIONS_DIR = "versions".freeze

    OPEN = "---\n".freeze
    CLOSE = "\n---\n".freeze

    ASSET_TIMES = %i[verified_at created_at updated_at deleted_at].freeze
    TASK_TIMES = %i[created_at updated_at].freeze

    module_function

    # `attrs` holds the front matter keys plus :content. Times may be Time or
    # ISO 8601 strings; they are written as UTC with microseconds.
    def dump_asset(attrs)
      content = attrs[:content]
      front = {
        "slug" => attrs[:slug],
        "owner" => attrs[:owner],
        "dir" => attrs[:dir],
        "name" => attrs[:name],
        "content_type" => attrs[:content_type],
        "content_nil" => content.nil?,
        "tags" => Array(attrs[:tags]),
        "status" => attrs[:status],
        "stale_after" => attrs[:stale_after],
        "verified_at" => time_string(attrs[:verified_at]),
        "created_at" => time_string(attrs[:created_at]),
        "updated_at" => time_string(attrs[:updated_at])
      }
      front["deleted_at"] = time_string(attrs[:deleted_at]) if attrs[:deleted_at]
      front["task"] = dump_task(attrs[:task]) if attrs[:task]

      yaml = Psych.safe_dump(front, permitted_classes: [ Date ])
      # Block scalars indent every line, so only a malformed dump could carry
      # the delimiter at column 0; refuse rather than write a file that splits wrong.
      raise InvalidError, "front matter for #{attrs[:slug]} contains a bare '---' line" if yaml.index(CLOSE, OPEN.size - 1)

      ((yaml + OPEN).b + content.to_s.b).force_encoding(Encoding::UTF_8)
    end

    # Parses one asset file. `file` names it in error messages.
    def load_asset(string, file: nil)
      text = string.b
      raise InvalidError, "#{label(file)}: does not start with front matter" unless text.start_with?(OPEN)

      stop = text.index(CLOSE, OPEN.size - 1)
      raise InvalidError, "#{label(file)}: front matter is not closed with '---'" unless stop

      front = parse_yaml(text[0...stop].force_encoding(Encoding::UTF_8), file)
      body = text[(stop + CLOSE.size)..].force_encoding(Encoding::UTF_8)
      raise InvalidError, "#{label(file)}: content is not valid UTF-8" unless body.valid_encoding?

      content_nil = front["content_nil"] == true
      raise InvalidError, "#{label(file)}: content_nil is true but the body is not empty" if content_nil && !body.empty?

      asset = {
        slug: front["slug"],
        owner: front["owner"],
        dir: front["dir"],
        name: front["name"],
        content_type: front["content_type"],
        content_nil:,
        content: content_nil ? nil : body,
        tags: Array(front["tags"]).map(&:to_s),
        status: front["status"],
        stale_after: parse_date(front["stale_after"], file),
        task: front["task"] && load_task(front["task"], file)
      }
      ASSET_TIMES.each { |key| asset[key] = parse_time(front[key.to_s], key, file) }
      asset
    end

    def asset_path(dir:, name:, slug:, archived:)
      archived ? File.join(ARCHIVED_DIR, slug, dir, name) : File.join(ASSETS_DIR, dir, name)
    end

    def versions_path(slug)
      File.join(VERSIONS_DIR, "#{slug}.jsonl")
    end

    # Each row: content, content_type, created_at, actor ("handle",
    # "handle/agent" or nil). Oldest first.
    def dump_versions(rows)
      rows.map do |row|
        JSON.generate(
          "content" => row[:content],
          "content_type" => row[:content_type],
          "created_at" => time_string(row[:created_at]),
          "actor" => row[:actor]
        ) + "\n"
      end.join
    end

    def load_versions(string, file: nil)
      string.each_line.reject { |line| line.strip.empty? }.map do |line|
        row = JSON.parse(line)
        raise InvalidError, "#{label(file)}: each line must be a JSON object" unless row.is_a?(Hash)

        {
          content: row["content"],
          content_type: row["content_type"],
          created_at: parse_time(row["created_at"], :created_at, file),
          actor: row["actor"]
        }
      end
    rescue JSON::ParserError => e
      raise InvalidError, "#{label(file)}: #{e.message}"
    end

    def dump_manifest(exported_at:, counts:, assets:)
      JSON.pretty_generate(
        "format" => NAME,
        "version" => VERSION,
        "exported_at" => time_string(exported_at),
        "counts" => counts.transform_keys(&:to_s),
        "assets" => assets.map { |a| { "slug" => a[:slug], "file" => a[:file], "sha256" => a[:sha256] } }
      ) + "\n"
    end

    def load_manifest(string, file: MANIFEST)
      data = JSON.parse(string)
      raise InvalidError, "#{file}: must be a JSON object" unless data.is_a?(Hash)
      raise InvalidError, "#{file}: format is #{data['format'].inspect}, not #{NAME.inspect}" unless data["format"] == NAME
      unless data["version"] == VERSION
        raise InvalidError, "#{file}: version #{data['version'].inspect} is not supported (this reads version #{VERSION})"
      end

      {
        format: data["format"],
        version: data["version"],
        exported_at: data["exported_at"],
        counts: (data["counts"] || {}).to_h { |k, v| [ k.to_sym, v ] },
        assets: Array(data["assets"]).map { |a| { slug: a["slug"], file: a["file"], sha256: a["sha256"] } }
      }
    rescue JSON::ParserError => e
      raise InvalidError, "#{file}: #{e.message}"
    end

    def dump_task(task)
      {
        "status" => task[:status],
        "attempts" => task[:attempts],
        "outcome_note" => task[:outcome_note],
        "created_at" => time_string(task[:created_at]),
        "updated_at" => time_string(task[:updated_at])
      }
    end

    def load_task(front, file)
      raise InvalidError, "#{label(file)}: task must be a mapping" unless front.is_a?(Hash)

      task = { status: front["status"], attempts: front["attempts"].to_i, outcome_note: front["outcome_note"] }
      TASK_TIMES.each { |key| task[key] = parse_time(front[key.to_s], key, file) }
      task
    end

    def parse_yaml(text, file)
      front = Psych.safe_load(text, permitted_classes: [ Date ])
      raise InvalidError, "#{label(file)}: front matter must be a mapping" unless front.is_a?(Hash)

      front
    rescue Psych::Exception => e
      raise InvalidError, "#{label(file)}: #{e.message}"
    end

    def time_string(value)
      case value
      when nil then nil
      when String then value
      else value.utc.iso8601(6)
      end
    end

    def parse_time(value, key, file)
      return nil if value.nil?

      Time.iso8601(value.to_s).utc
    rescue ArgumentError
      raise InvalidError, "#{label(file)}: #{key} is not an ISO 8601 time: #{value.inspect}"
    end

    def parse_date(value, file)
      return nil if value.nil?
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError
      raise InvalidError, "#{label(file)}: stale_after is not an ISO date: #{value.inspect}"
    end

    def label(file)
      file || "asset file"
    end
  end
end
