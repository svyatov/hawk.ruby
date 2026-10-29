# frozen_string_literal: true

require "open3"
require "rbconfig"

module Subprocess
  def self.run(program, environment = {})
    bootstrap = File.expand_path("coverage_start.rb", __dir__)
    Open3.capture3(environment, RbConfig.ruby, "-r#{bootstrap}",
                   "-I#{File.expand_path('../../lib', __dir__)}", "-e", program)
  end
end
