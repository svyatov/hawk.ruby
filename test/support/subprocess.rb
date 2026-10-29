# frozen_string_literal: true

require "open3"
require "rbconfig"

module Subprocess
  def self.run(program, environment = {})
    Open3.capture3(environment, RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", "-e", program)
  end
end
