module Tasks
  # Creates a task: an ordinary asset under the actor's workspace plus the
  # facet row that makes it one. The asset, its facet and the task_added
  # event commit together; a task without its facet row is a note, so the
  # event Assets::Create would record is replaced rather than added to.
  class Add
    ForbiddenError = Assets::ForbiddenError
    NameTakenError = Assets::NameTakenError
    InvalidNameError = Asset::InvalidNameError
    InvalidDirError = Asset::InvalidDirError
    ReservedDirError = Asset::ReservedDirError

    def self.mutate(actor:, path:, name:, content: nil, content_type: nil, tags: [])
      ActiveRecord::Base.transaction do
        asset = Assets::Create.mutate(actor:, path:, name:, content:, content_type:, tags:, event: "task_added")
        Task.create!(asset:, status: "pending")
        asset
      end
    end
  end
end
