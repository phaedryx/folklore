ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

OmniAuth.config.test_mode = true
OmniAuth.config.logger = Rails.logger

Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    teardown do
      OmniAuth.config.mock_auth.clear
    end

    def actor_for(fixture_name, agent: nil)
      Actor.for_token(tokens(fixture_name), agent:)
    end

    def actor_context(fixture_name = :member_default, agent: nil)
      { actor: actor_for(fixture_name, agent:) }
    end

    def text_of(response)
      response.to_h[:content].first[:text]
    end
  end
end
