# frozen_string_literal: true

require_relative "release/publication"

HawkRelease::Publication.new(
  "pkg",
  tag: ENV.fetch("GITHUB_REF_NAME"),
  commit: ENV.fetch("GITHUB_SHA"),
  repository: ENV.fetch("GH_REPO")
).publish
