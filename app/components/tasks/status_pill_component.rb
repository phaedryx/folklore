module Tasks
  # A task's lifecycle status as a coloured pill.
  class StatusPillComponent < ViewComponent::Base
    STATUS_CLASSES = {
      "pending" => "bg-surface-200 text-surface-800",
      "in_progress" => "bg-primary-soft text-primary-hover",
      "done" => "bg-success-100 text-success-800",
      "failed" => "bg-error-100 text-error-800",
      "cancelled" => "bg-warning-100 text-warning-800"
    }.freeze

    def initialize(status:)
      @status = status
    end

    def classes = STATUS_CLASSES.fetch(@status, STATUS_CLASSES["pending"])

    def label = @status.tr("_", " ")
  end
end
