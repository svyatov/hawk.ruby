# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class PackageTest < HawkTest
  def test_installed_core_and_signatures_have_no_framework_dependency
    output, error, status = Open3.capture3(RbConfig.ruby, "script/check_package.rb")
    assert status.success?, "#{output}\n#{error}"
    report = JSON.parse(output.lines.last)

    assert_equal "0.1.1", report.fetch("version")
    assert_empty report.fetch("frameworks")
    assert_equal 0, report.fetch("new_threads")
    assert_equal Dir["lib/**/*.rb"].tally, report.fetch("runtime_files").tally
    assert_equal true, report.fetch("source_hashes_match")
    assert_equal true, report.fetch("signatures_valid")
    assert_equal true, report.fetch("optional_adapters_isolated")
    assert_equal "installed artifact", report.fetch("event_title")
  end
end
