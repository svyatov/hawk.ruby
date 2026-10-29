# frozen_string_literal: true

# Use a workspace-local database so a failed refresh cannot look like a clean audit.
root = File.expand_path("..", __dir__)
database = File.join(root, ".superpowers/ruby-advisory-db")
locks = ["Gemfile.lock", *Dir.glob("gemfiles/*.gemfile.lock", base: root)].sort
locks.each do |lock|
  puts "Auditing #{lock}"
  command = ["bundle", "exec", "bundle-audit", "check", "--update", "--database", database,
             "--gemfile-lock", lock]
  abort "Audit failed: #{lock}" unless system(*command, chdir: root)
end
