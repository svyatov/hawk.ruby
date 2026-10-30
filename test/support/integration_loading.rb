# frozen_string_literal: true

require "support/subprocess"

module IntegrationLoading
  def assert_startup_loading(library, assertion)
    [[library, "hawk"], ["hawk", library]].each do |libraries|
      output, error, status = Subprocess.run(<<~RUBY)
        #{libraries.map { |name| "require #{name.inspect}" }.join("\n")}
        2.times { Hawk.init { |config| config.token = nil } }
        print(#{assertion})
      RUBY
      assert status.success?, error
      assert_equal "true", output
    end
  end
end
