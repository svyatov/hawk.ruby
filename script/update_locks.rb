# frozen_string_literal: true

root = File.expand_path("..", __dir__)
gemfiles = ["Gemfile", *Dir.glob("gemfiles/*.gemfile", base: root)]
gemfiles.each do |path|
  gemfile = File.join(root, path)
  environment = { "BUNDLE_GEMFILE" => gemfile, "BUNDLE_LOCKFILE" => "#{gemfile}.lock",
                  "BUNDLE_FROZEN" => "false", "BUNDLE_DEPLOYMENT" => "false" }
  abort "Lockfile update failed: #{path}" unless system(environment, "bundle", "lock", "--update", chdir: root)
end
