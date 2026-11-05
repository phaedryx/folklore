# The task facet of an asset: its presence makes the asset a task. Claims are
# leased and recorded against (user, agent), so two agents on one token
# exclude each other. A task may depend on other tasks; it is ready to claim
# only once every one of them is done.
class Task < ApplicationRecord
  self.primary_key = "asset_id"

  belongs_to :asset
  belongs_to :claimed_by_token, class_name: "Token", optional: true
  belongs_to :claimed_by_user, class_name: "User", optional: true
  has_many :task_dependencies, foreign_key: :task_asset_id, inverse_of: :task
  has_many :dependencies, through: :task_dependencies, source: :depends_on

  STATUSES = %w[pending in_progress done failed cancelled].freeze
  # Mirrors the CHECK constraint on tasks.outcome_note.
  MAX_NOTE_LENGTH = 10_000

  # True of a tasks row that waits on a dependency: one not done, or whose
  # asset is archived. Failure does not cascade, so a failed or cancelled
  # dependency blocks its dependents until a person sorts it out. Written
  # against the `tasks` alias so it works wherever that table is in scope,
  # including inside the locked claim query.
  BLOCKED_SQL = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM task_dependencies td
      JOIN tasks dep ON dep.asset_id = td.depends_on_asset_id
      JOIN assets dep_asset ON dep_asset.id = dep.asset_id
      WHERE td.task_asset_id = tasks.asset_id
        AND (dep.status <> 'done' OR dep_asset.deleted_at IS NOT NULL)
    )
  SQL

  scope :ready,   -> { where("NOT #{BLOCKED_SQL}") }
  scope :blocked, -> { where(BLOCKED_SQL) }

  validates :status, inclusion: { in: STATUSES }

  def lease_expired?
    lease_until.present? && lease_until < Time.current
  end

  # Dependencies oldest first, from the loaded association: callers preload
  # `dependencies: :asset`.
  def dependencies_by_creation
    dependencies.sort_by { |dep| [ dep.asset.created_at, dep.asset.id ] }
  end

  # The dependencies that still block this task (the Ruby reading of BLOCKED_SQL).
  def blockers
    dependencies_by_creation.select { |dep| dep.status != "done" || dep.asset.deleted_at? }
  end
end
