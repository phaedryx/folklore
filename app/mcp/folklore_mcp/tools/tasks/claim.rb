module FolkloreMcp
  module Tools
    module Tasks
      class Claim < FolkloreMcp::Tool
        tool_name "claim_task"
        description "Claim a task under a lease, as your agent. Pass a slug to claim that task, or " \
                    "omit it and pass path_prefix (and optionally tags) to claim the oldest ready " \
                    "task there. Atomic: only one claimer wins. A task whose dependencies are not all " \
                    "done is Blocked by slug and passed over by path_prefix; when only blocked tasks " \
                    "remain, No pending task says how many wait. The response carries each dependency's " \
                    "outcome note. A claim belongs to (you, token, agent): pass " \
                    "agent when several agents share one token, so they exclude each other. Claiming a " \
                    "task you already hold renews its lease; a task whose lease (lease_seconds, default " \
                    "1800) has run out can be claimed by anyone. Finish it with complete_task or fail_task."

        input_schema do
          optional(:slug).filled(:string)
          optional(:path_prefix).filled(:string)
          optional(:tags).array(:string)
          optional(:lease_seconds).filled(:integer)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:claimed_by).filled(:string)
          required(:lease_until).filled(:string)
          required(:attempts).filled(:integer)
          required(:dependencies).array(:hash) do
            required(:slug).filled(:string)
            required(:location).filled(:string)
            required(:outcome_note).maybe(:string)
          end
        end

        def invoke(server_context:, slug: nil, path_prefix: nil, tags: [], lease_seconds: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Tasks::Claim.mutate(actor:, slug:, path_prefix:, tags:, lease_seconds:)
          task = Task.preload(:claimed_by_user, dependencies: :asset).find(asset.id)
          dependencies = task.dependencies_by_creation.map do |dep|
            { slug: dep.asset.slug, location: dep.asset.location, outcome_note: dep.outcome_note }
          end
          data = { slug: asset.slug, location: asset.location, claimed_by: Tasks.claimed_by(task),
                   lease_until: task.lease_until.iso8601, attempts: task.attempts, dependencies: }

          # The handoff: what the work this task builds on left behind.
          text = "Claimed #{asset.slug} at #{asset.location} as #{data[:claimed_by]} until #{data[:lease_until]}"
          dependencies.each do |dep|
            text += "\ndepends on #{dep[:slug]} #{dep[:location]}"
            text += ": #{dep[:outcome_note]}" if dep[:outcome_note]
          end
          text_response(text, data:)
        end
      end
    end
  end
end
