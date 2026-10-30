# frozen_string_literal: true

require "test_helper"
require "support/subprocess"

class RailsLoadingTest < HawkTest
  def test_normal_bundler_loading_installs_rails_middleware
    output, error, status = Subprocess.run(<<~RUBY)
      require "rails/all"
      require "bundler"
      Bundler.require
      class StartupApp < Rails::Application
        config.eager_load = false
        config.secret_key_base = "test"
        config.logger = Logger.new(File::NULL)
        initializer "test.hawk", before: "hawk.middleware" do
          Hawk.init { |config| config.token = nil }
        end
      end
      StartupApp.initialize!
      print StartupApp.middleware.count { |entry| entry.klass == Hawk::Rack }
    RUBY

    assert status.success?, error
    assert_equal "1", output
  end

  def test_rails_loaded_between_hawk_and_initialization_is_discovered
    output, error, status = Subprocess.run(<<~RUBY)
      require "hawk"
      require "rails"
      require "action_controller/railtie"
      Hawk.init { |config| config.token = nil }
      print defined?(Hawk::Railtie)
    RUBY

    assert status.success?, error
    assert_equal "constant", output
  end
end
