# frozen_string_literal: true

require_relative "../lib/hawk/version"

abort "Release requires a tag" unless ENV.fetch("GITHUB_REF_TYPE") == "tag"
abort "Tag and gem version differ" unless ENV.fetch("GITHUB_REF_NAME") == "v#{Hawk::VERSION}"
abort "Release commit must belong to main" unless system("git", "merge-base", "--is-ancestor", "HEAD", "origin/main")
