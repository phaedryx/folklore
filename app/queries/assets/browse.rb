module Assets
  # One directory of the file browser: the live assets directly in it and the
  # names of the folders one level below. Folders exist only through the
  # live assets under them, so a folder of archived files disappears.
  class Browse
    # A task is listed once, as a task, whatever else it is tagged.
    Listing = Data.define(:files, :folders) do
      def tasks = files.select(&:task?)
      def decisions = (files - tasks).select { |a| a.tags.any? { |t| t.name == "decision" } }
      def failures = (files - tasks).select { |a| a.tags.any? { |t| t.name == "failure" } }
      def other_files = files - tasks - decisions - failures
      def empty? = files.empty? && folders.empty?
    end

    def self.query(dir:, actor: nil)
      dir = dir.to_s
      files = Asset.live.where(dir:).includes(:tags, task: :claimed_by_user).order(:name).to_a
      prefix = "#{dir}/"
      folders = Asset.live.under_dir(dir).where.not(dir:).distinct.pluck(:dir)
                     .map { |d| d.delete_prefix(prefix).split("/").first }
                     .uniq.sort
      Listing.new(files:, folders:)
    end
  end
end
