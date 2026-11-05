module Tasks
  # Creates a task: an ordinary asset under the actor's workspace plus the
  # facet row that makes it one. The asset, its facet and the task_added
  # event commit together; a task without its facet row is a note, so the
  # event Assets::Create would record is replaced rather than added to.
  #
  # `depends_on` names, by slug, the tasks this one waits for: it cannot be
  # claimed until every one of them is done. Dependencies are set here and
  # nowhere else. A task that does not exist yet can only depend on tasks that
  # already do, so the graph is acyclic by construction and no cycle check is
  # needed. The slugs are kept in the task_added event's metadata.
  class Add
    ForbiddenError = Assets::ForbiddenError
    NameTakenError = Assets::NameTakenError
    NotFoundError = Assets::NotFoundError
    InvalidNameError = Asset::InvalidNameError
    InvalidDirError = Asset::InvalidDirError
    ReservedDirError = Asset::ReservedDirError

    def self.mutate(actor:, path:, name:, content: nil, content_type: nil, tags: [], depends_on: [])
      ActiveRecord::Base.transaction do
        dependencies = resolve(depends_on)
        metadata = dependencies.any? ? { "depends_on" => dependencies.map(&:slug) } : {}
        asset = Assets::Create.mutate(actor:, path:, name:, content:, content_type:, tags:, event: "task_added", metadata:)
        Task.create!(asset:, status: "pending")
        dependencies.each { |dependency| TaskDependency.create!(task_asset_id: asset.id, depends_on_asset_id: dependency.id) }
        asset
      end
    end

    # The live task asset behind each slug, in the order given and without
    # repeats. Any slug that is not one refuses the whole call, naming it.
    def self.resolve(slugs)
      Array(slugs).map(&:to_s).uniq.map do |slug|
        asset = Asset.live.find_by(slug:)
        raise NotFoundError, slug unless asset
        raise NotATaskError, slug unless Task.exists?(asset_id: asset.id)

        asset
      end
    end
    private_class_method :resolve
  end
end
