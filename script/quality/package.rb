# frozen_string_literal: true

module HawkQuality
  # Builds and installs the artifact into a gem home containing only runtime gems.
  class Package
    LIBRARIES = %w[base64 json uri open3 securerandom net-http timeout time logger].freeze
    OPTIONAL = { "rails" => "rails/railtie", "rake" => "rake", "sidekiq" => "sidekiq",
                 "resque" => "resque", "delayed_job" => "delayed_job" }.freeze

    def initialize(directory)
      @directory = directory
      @root = File.expand_path("../..", __dir__)
      @artifact = File.join(directory, "hawk.gem")
      @home = File.join(directory, "gems")
    end

    def check
      command(RbConfig.ruby, gem_command, "build", "hawk-ruby.gemspec", "--output", @artifact)
      spec = Gem::Package.new(@artifact).spec
      verify_contents(spec)
      install(spec)
      installed = File.join(@home, "gems", spec.full_name)
      hashes_match = verify_sources(installed)
      result = exercise_core(installed)
      result.merge("runtime_files" => Dir.glob("lib/**/*.rb", base: installed).sort,
                   "source_hashes_match" => hashes_match, "signatures_valid" => signatures_valid?(installed),
                   "optional_adapters_isolated" => optional_adapters_isolated?)
    end

    private

    def gem_command
      File.join(RbConfig::CONFIG.fetch("bindir"), "gem")
    end

    def command(*arguments, environment: Bundler.unbundled_env)
      output, status = Open3.capture2e(environment, *arguments, chdir: @root)
      raise "Package command failed: #{arguments.join(' ')}\n#{output}" unless status.success?

      output
    end

    def verify_contents(spec)
      expected = Dir.glob("{lib/**/*.rb,sig/hawk.rbs,sig/hawk/**/*.rbs,docs/*.md}", base: @root)
      expected += %w[LICENSE README.md CHANGELOG.md]
      raise "Unexpected package contents" unless spec.files.sort == expected.sort
    end

    def runtime_specs(dependencies, found = {})
      dependencies.each do |dependency|
        spec = Gem::Specification.find_by_name(dependency.name, dependency.requirement)
        next if found.key?(spec.name)

        found[spec.name] = spec
        runtime_specs(spec.runtime_dependencies, found)
      end
      found.values
    end

    def install(spec)
      caches = runtime_specs(spec.runtime_dependencies).reject(&:default_gem?).map(&:cache_file)
      raise "Runtime gem cache is missing" unless caches.all? { |path| File.file?(path) }

      command(RbConfig.ruby, gem_command, "install", "--local", "--ignore-dependencies", "--no-document",
              "--install-dir", @home, *caches, @artifact)
      @gemfile = File.join(@directory, "Gemfile")
      File.write(@gemfile, "source 'https://rubygems.org'\ngem 'hawk-ruby', '= #{spec.version}'\n")
    end

    def environment
      Bundler.unbundled_env.merge("GEM_HOME" => @home, "GEM_PATH" => @home, "RUBYLIB" => nil,
                                  "BUNDLE_GEMFILE" => @gemfile, "BUNDLE_LOCKFILE" => "#{@gemfile}.lock")
    end

    def verify_sources(installed)
      files = Dir.glob("lib/**/*.rb", base: @root)
      valid = files.all? do |path|
        packaged = Digest::SHA256.file(File.join(installed, path)).hexdigest
        packaged == Digest::SHA256.file(File.join(@root, path)).hexdigest
      end
      raise "Packaged sources differ from checked sources" unless valid

      valid
    end

    def exercise_core(installed)
      collector = Collector.new
      result = core_result(installed, collector.url)
      raise "Installed event was not received once" unless collector.events.size == 1

      result.merge("event_title" => collector.events.first.dig("payload", "title"))
    ensure
      collector&.close
    end

    def core_result(installed, url)
      env = environment.merge("HAWK_PACKAGE_COLLECTOR" => url, "HAWK_PACKAGE_ROOT" => installed)
      command(RbConfig.ruby, "-rbundler/setup", "-e", "nil", environment: env)
      output = command(RbConfig.ruby, "test/fixtures/installed_core.rb", environment: env)
      JSON.parse(output.lines.last)
    end

    def signatures_valid?(installed)
      arguments = LIBRARIES.flat_map { |library| ["-r", library] }
      command("bundle", "exec", "rbs", "-I", File.join(installed, "sig"), *arguments, "validate",
              environment: ENV.to_h)
      true
    end

    def optional_adapters_isolated?
      command(RbConfig.ruby, "-rbundler/setup", "-e", 'require "hawk/rack"', environment: environment)
      OPTIONAL.each do |adapter, dependency|
        _output, error, status = Open3.capture3(environment, RbConfig.ruby, "-rbundler/setup", "-e",
                                                "require 'hawk/#{adapter}'")
        if status.success? || !error.include?(dependency)
          raise "Optional adapter #{adapter} did not isolate its dependency"
        end
      end
      true
    end
  end
end
