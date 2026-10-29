# Changelog

All notable changes to this project are documented here, following [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/).

Versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) for the [declared public API](docs/public-api.md).

## [Unreleased]

## [0.1.1] - 2026-10-29

### Added

- Document the public API, contribution process, and private reporting channels.
- Publish an inventory of the packaged files and runtime requirements, with signed provenance for release assets.

### Changed

- Clarify installation, first capture, and default privacy controls.
- Require approval before publication and upload provenance with the gem to RubyGems.
- Check pull requests for new dependency vulnerabilities and report existing findings each week.

## [0.1.0] - 2026-10-29

Initial release of the Hawk Ruby error reporting gem.

### Added

- Report exceptions and messages with backtraces, source snippets, breadcrumbs, user data, context, severity, and application release identifiers.
- Add optional Rack, Rails, Rails error reporter, Action Cable, Active Job, Solid Queue, Sidekiq, Resque, Delayed Job, and Rake integration.
- Provide bounded asynchronous delivery, execution-local scopes, duplicate suppression, fork recovery, privacy filters, and event hooks.
- Ship RBS signatures and enforce complete type coverage, 100% line and branch coverage, and measured CRAP scores no greater than 10.

[Unreleased]: https://github.com/svyatov/hawk.ruby/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/svyatov/hawk.ruby/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/svyatov/hawk.ruby/releases/tag/v0.1.0
