module Tasks
  # Marks a held task done, with an optional outcome note.
  class Complete
    def self.mutate(actor:, slug:, note: nil)
      note = note.to_s.strip.presence
      Tasks.validate_note!(note, "note")
      Finish.mutate(actor:, slug:, status: "done", action: "task_completed", note:,
                    metadata: note ? { "note" => note } : {})
    end
  end
end
