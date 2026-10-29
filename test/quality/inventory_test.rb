# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../script/release/inventory"

class InventoryTest < HawkTest
  def test_inventory_hashes_the_artifact_and_every_packaged_file
    Dir.mktmpdir("hawk-inventory") do |directory|
      path = File.join(directory, "hawk.gem")
      spec = Gem::Specification.load("hawk-ruby.gemspec")
      Gem::Package.build(spec, false, false, path)
      document = HawkRelease::Inventory.new(path).document

      assert_equal Digest::SHA256.file(path).hexdigest, document.dig(:metadata, :component, :hashes, 0, :content)
      files = document.fetch(:components).select { |item| item[:type] == "file" }
      assert_equal spec.files.sort, files.map { |item| item.fetch(:name) }.sort
      files.each do |file|
        assert_equal Digest::SHA256.file(file.fetch(:name)).hexdigest, file.dig(:hashes, 0, :content)
      end
      assert_requirements(document, spec)
    end
  end

  def test_invalid_artifact_is_rejected
    Dir.mktmpdir("hawk-inventory") do |directory|
      path = File.join(directory, "invalid.gem")
      File.write(path, "invalid")
      assert_raises(Gem::Package::FormatError) { HawkRelease::Inventory.new(path) }
    end
  end

  private

  def assert_requirements(document, spec)
    requirements = document.fetch(:components).select { |item| item[:type] == "library" }
    assert_equal spec.runtime_dependencies.map(&:name).sort, requirements.map { |item| item[:name] }.sort
    requirements.each do |item|
      assert_includes item[:properties], { name: "hawk:bundled", value: "false" }
    end
    ruby = document.fetch(:components).find { |item| item[:"bom-ref"] == "runtime:Ruby" }
    assert_includes ruby.fetch(:properties), { name: "hawk:version-requirement", value: ">= 3.3" }
  end
end
