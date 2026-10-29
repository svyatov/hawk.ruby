# frozen_string_literal: true

require "digest"
require "json"
require "rubygems/package"
require "stringio"
require "zlib"

module HawkRelease
  # Describe the packaged bytes, not the development dependency graph.
  class Inventory
    def initialize(path)
      @path = path
      @package = Gem::Package.new(path)
      @package.verify
      @spec = @package.spec
    end

    def document
      files = packaged_files
      runtime = @spec.runtime_dependencies.map { |dependency| requirement(dependency) } + [ruby_requirement]
      references = (files + runtime).map { |item| item.fetch(:"bom-ref") }
      {
        bomFormat: "CycloneDX", specVersion: "1.6", version: 1,
        metadata: { component: component, tools: { components: build_tools } },
        components: files + runtime,
        dependencies: [{ ref: component.fetch(:"bom-ref"), dependsOn: references }]
      }
    end

    private

    def component
      {
        type: "library", "bom-ref": "gem:#{@spec.full_name}", name: @spec.name, version: @spec.version.to_s,
        purl: "pkg:gem/#{@spec.name}@#{@spec.version}", licenses: @spec.licenses.map { |id| { license: { id: id } } },
        hashes: [{ alg: "SHA-256", content: Digest::SHA256.file(@path).hexdigest }],
        properties: [{ name: "hawk:runtime-dependencies",
                       value: "Declared requirements are external, not bundled or resolved by this artifact." }]
      }
    end

    def packaged_files
      File.open(@path, "rb") do |file|
        Gem::Package::TarReader.new(file).each do |entry|
          next unless entry.full_name == "data.tar.gz"

          return read_files(Zlib::GzipReader.new(StringIO.new(entry.read)))
        end
      end
      raise Gem::Package::FormatError, "Gem has no data.tar.gz"
    end

    def read_files(archive)
      files = Gem::Package::TarReader.new(archive).filter_map do |entry|
        next unless entry.file?

        { type: "file", "bom-ref": "file:#{entry.full_name}", name: entry.full_name,
          hashes: [{ alg: "SHA-256", content: Digest::SHA256.hexdigest(entry.read) }] }
      end
      files.sort_by { |entry| entry.fetch(:name) }
    end

    def requirement(dependency)
      {
        type: "library", "bom-ref": "requirement:#{dependency.name}", name: dependency.name,
        purl: "pkg:gem/#{dependency.name}", scope: "required",
        properties: [{ name: "hawk:version-requirement", value: dependency.requirement.to_s },
                     { name: "hawk:bundled", value: "false" }]
      }
    end

    def build_tools
      [{ type: "application", name: "Ruby", version: RUBY_VERSION },
       { type: "application", name: "RubyGems", version: Gem::VERSION }]
    end

    def ruby_requirement
      {
        type: "application", "bom-ref": "runtime:Ruby", name: "Ruby", scope: "required",
        properties: [{ name: "hawk:version-requirement", value: @spec.required_ruby_version.to_s },
                     { name: "hawk:bundled", value: "false" }]
      }
    end
  end
end
