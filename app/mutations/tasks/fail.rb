module Tasks
  # Marks a held task failed. The reason is required: it is the escalation
  # trail, kept on the task and in the event.
  class Fail
    def self.mutate(actor:, slug:, reason:)
      reason = reason.to_s.strip
      raise ReasonRequiredError, "a reason is required to fail a task" if reason.empty?
      Tasks.validate_note!(reason, "reason", error: ReasonTooLongError)

      Finish.mutate(actor:, slug:, status: "failed", action: "task_failed", note: reason,
                    metadata: { "reason" => reason })
    end
  end
end
