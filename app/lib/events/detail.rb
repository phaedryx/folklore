module Events
  # The one-line detail of an event's metadata, shared by the activity page
  # and the `activity` tool: a lease renewal reads as one, an expired lease
  # names the claimer who lost it, and a cleared value says so.
  module Detail
    LABELS = {
      "tag" => "tag", "note" => "note", "reason" => "reason",
      "stale_after" => "review after", "status" => "status"
    }.freeze

    def self.call(event)
      metadata = event.metadata.to_h
      parts = case event.action
      when "task_claimed"
        [ ("renewal" if metadata["renewal"]), lease("lease until", metadata["lease_until"]) ]
      when "task_lease_expired"
        [ "#{metadata['claimed_by']}'s lease ended #{metadata['lease_until']}" ]
      when "version_restored"
        [ "from version #{metadata['restored_from_version_id']}" ]
      else
        LABELS.filter_map { |key, label| "#{label}: #{metadata[key].presence || 'cleared'}" if metadata.key?(key) }
      end
      parts.compact.join(" · ")
    end

    def self.lease(label, value)
      "#{label} #{value}" if value
    end
  end
end
