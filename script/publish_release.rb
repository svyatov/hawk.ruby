# frozen_string_literal: true

require_relative "release/publication"

publication = HawkRelease::Publication.new(
  "pkg",
  tag: ENV.fetch("GITHUB_REF_NAME"),
  commit: ENV.fetch("GITHUB_SHA"),
  repository: ENV.fetch("GH_REPO")
)

case ARGV.fetch(0)
when "gem" then publication.publish_gem(attestation: ENV.fetch("GEM_ATTESTATION"))
when "github" then publication.publish_github
else abort "Usage: ruby script/publish_release.rb gem|github"
end
