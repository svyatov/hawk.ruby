# frozen_string_literal: true

require "support/collector"
require "support/rails_app"

class RailsCaptureTest < HawkTest
  def setup
    @collector = Collector.new
    initialize_hawk
  end

  def teardown
    Hawk.close
    @collector.close
  end

  def initialize_hawk
    Hawk.init do |config|
      config.token = integration_token
      config.endpoint = @collector.url
      config.delivery_mode = :sync
      config.global_errors = false
    end
  end
end
