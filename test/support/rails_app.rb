# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "solid_queue"
require "rack/mock"
require "logger"
require "tmpdir"
require "hawk/rails"

class HawkFixtureController < ActionController::Base
  def ok
    render plain: "ok"
  end

  def boom
    params.to_unsafe_h
    raise "controller failed"
  end

  def missing
    raise ActiveRecord::RecordNotFound, "missing record"
  end

  def scoped
    Hawk.set_context(private_scope: "request-only")
    render plain: "scoped"
  end
end

class HawkFixtureApp < Rails::Application
  config.root = Dir.mktmpdir("hawk-rails")
  config.eager_load = false
  config.secret_key_base = "hawk-fixture-secret" * 4
  config.hosts.clear
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :all
  config.action_dispatch.rescue_responses["ActiveRecord::RecordNotFound"] = :not_found
  config.filter_parameters += [:pin]
  config.logger = Logger.new(File::NULL)
end

FileUtils.mkdir_p(File.join(HawkFixtureApp.config.root, "config"))
File.write(File.join(HawkFixtureApp.config.root, "config/database.yml"),
           "development:\n  adapter: sqlite3\n  database: ':memory:'\n")
HawkFixtureApp.initialize!
HawkFixtureApp.routes.draw do
  get "/ok", to: "hawk_fixture#ok"
  get "/boom", to: "hawk_fixture#boom"
  get "/missing", to: "hawk_fixture#missing"
  get "/scoped", to: "hawk_fixture#scoped"
end
