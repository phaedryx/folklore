module SearchEval
  # Runs the eval over the invented corpus and queries committed in script/search_eval/, so
  # the numbers in docs/search.md can be reproduced by anyone: `bin/rails folklore:search_eval`.
  #
  # The corpus is loaded inside a transaction that is rolled back, under a directory of its
  # own, and the eval is confined to that directory. Search ranks within its filters, so the
  # rest of the database neither shows up in the results nor shifts their order.
  class Synthetic
    DIR = Rails.root.join("script/search_eval")
    HANDLE = "search-eval".freeze

    def self.call(out: $stdout)
      new(out:).call
    end

    def initialize(out:)
      @out = out
    end

    def call
      ActiveRecord::Base.transaction do
        load_corpus
        @out.puts "synthetic corpus: #{DIR.relative_path_from(Rails.root)}"
        Runner.new(DIR.join("queries.yml"), out: @out, within: HANDLE).call
        raise ActiveRecord::Rollback
      end
    end

    private

    def load_corpus
      owner = User.find_by(handle: HANDLE) ||
              User.create!(handle: HANDLE, email: "#{HANDLE}@example.invalid", name: "Search eval")

      YAML.load_file(DIR.join("corpus.yml")).each do |entry|
        Asset.create!(owner:, slug: entry["slug"], dir: "#{HANDLE}/#{entry['dir']}", name: entry["name"],
                      content: entry["content"])
      end
    end
  end
end
