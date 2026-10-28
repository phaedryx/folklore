module Assets
  # One live asset by address: either a full location ("member/notes/a.md")
  # or a dir plus a name.
  class ReadByPath
    NotFoundError = Assets::NotFoundError
    InvalidLocationError = Assets::InvalidLocationError

    def self.query(location: nil, path: nil, name: nil, actor: nil)
      dir, leaf = resolve(location:, path:, name:)
      Asset.live.find_by(dir:, name: leaf) or raise NotFoundError, "#{dir}/#{leaf}"
    end

    def self.resolve(location:, path:, name:)
      if location.present?
        segments = location.split("/", -1)
        leaf = segments.pop
        raise InvalidLocationError, "location must include a filename" if leaf.blank?
        raise InvalidLocationError, "location must include a workspace handle" if segments.empty?

        [ segments.join("/"), leaf ]
      elsif path.present? && name.present?
        [ path, name ]
      else
        raise InvalidLocationError, "provide location or path + name"
      end
    end
    private_class_method :resolve
  end
end
