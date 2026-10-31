module Assets
  # One live asset by its full location ("member/notes/a.md").
  class ReadByPath
    NotFoundError = Assets::NotFoundError
    InvalidLocationError = Assets::InvalidLocationError

    def self.query(location:, actor: nil)
      dir, leaf = resolve(location)
      Asset.live.find_by(dir:, name: leaf) or raise NotFoundError, "#{dir}/#{leaf}"
    end

    def self.resolve(location)
      segments = location.to_s.split("/", -1)
      leaf = segments.pop
      raise InvalidLocationError, "location must include a filename" if leaf.blank?
      raise InvalidLocationError, "location must include a workspace handle" if segments.empty?

      [ segments.join("/"), leaf ]
    end
    private_class_method :resolve
  end
end
