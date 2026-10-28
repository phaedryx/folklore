module Assets
  # One directory of the file browser: the live assets directly in it and the
  # names of the folders one level below. Folders exist only through the
  # live assets under them, so a folder of archived files disappears.
  class Browse
    GROUP_TAGS = %w[decision failure].freeze

    Listing = Data.define(:files, :folders) do
      def decisions = files.select { |a| a.tags.any? { |t| t.name == "decision" } }
      def failures = files.select { |a| a.tags.any? { |t| t.name == "failure" } }
      def other_files = files - decisions - failures
      def empty? = files.empty? && folders.empty?
    end

    def self.query(dir:, actor: nil)
      dir = dir.to_s
      files = Asset.live.where(dir:).includes(:tags).order(:name).to_a
      prefix = "#{dir}/"
      folders = Asset.live.under_dir(dir).where.not(dir:).distinct.pluck(:dir)
                     .map { |d| d.delete_prefix(prefix).split("/").first }
                     .uniq.sort
      Listing.new(files:, folders:)
    end
  end
end
