# Verification

## Local acceptance

The implementation was tested on macOS with CRuby 3.3.11, 3.4.9, and 4.0.9.

All 39 supported runtime combinations passed. Each Ruby's 13 lanes reached 100% line and branch coverage after merging fresh subprocess and fork reports.

The matrix includes separate Rack 2 and 3 bundles, all three Rails versions, Cable, Active Job, and real job backend fixtures.

Redis fixtures start isolated servers. Database fixtures use temporary SQLite files. Tests do not reuse application queues or databases.

| Gate | Observed result |
| --- | --- |
| RuboCop 1.92.2 | No offenses |
| Steep 2.1.0 and Ruby Signature (RBS) 4.2.0 | 37 runtime files, zero untyped calls, valid signatures |
| SimpleCov 1.3.2 | 100% executable lines and branches |
| crap4ruby 0.2.1 | All method scores measured, maximum CRAP 7, limit 10 |
| bundler-audit 0.9.3 | 13 lockfiles, no reported vulnerabilities after database refresh |

Negative gate fixtures reject omitted files, duplicate statistics, failed analysis, untyped calls, invalid counts, unchecked casts, and blanket suppressions.

Coverage fixtures reject stale revisions, changed sources, missing lanes, missing runtime files, and uncovered lines or branches. CRAP checks reject unknown method scores.

Steep internal crashes fail the gate even when Steep returns a successful exit status. Coverage receipts bind CRAP input to the verified source hashes and report hash.

## Resolved framework fixtures

| Family | Resolved versions |
| --- | --- |
| Rails | 7.2.4, 8.0.5.1, 8.1.4 |
| Rack | 2.2.24, 3.2.7 |
| Sidekiq | 7.3.10, 8.1.7 |
| Resque | 2.7.0 |
| Delayed Job and its Active Record backend | 4.2.0, 4.1.11 |
| Solid Queue and SQLite | 1.7.0, 2.10.2 |
| Rake | 13.4.2 |

Sidekiq 7 uses Rails 7.2 and 8.1 fixtures. Sidekiq 8 uses Rails 8.1. Bundler rejects Sidekiq 8.1.7 with Rails 7.2.4 because their `connection_pool` requirements conflict.

The matrix is defined in `script/test_lanes.rb`. GitHub Actions consumes that definition and requires all 39 lanes before coverage merging.

## Installed artifact acceptance

Independent runtime QA passed 44 public-interface scenarios on Ruby 4.0.9, including Rails reports and Active Job propagation.

The pass reproduced two defects and verified their fixes: request metadata timing and nonstandard hook exceptions. Regression tests cover both paths.

Final-review regressions and focused public-interface QA also verify cookie controls, Rails parameter roots, bounded duplicate retention, hook logging, integration reinitialization, and filtered job propagation.

`bundle exec rake test:package` builds the gem and installs it into a temporary gem home with only runtime dependencies.

The fixture loads the installed artifact in a core-only Bundler environment. It checks plain-load thread behavior and sends one event to a loopback collector.

The checker compares every packaged runtime file with its checked source, validates installed RBS signatures, and tests isolation from missing optional dependencies.

The package excludes development dependencies, external framework signatures, test fixtures, execution ledgers, coverage reports, and planning documents.

## Reproduce

Install the core bundle and each framework bundle first. Run these checks from the repository root:

```sh
bundle exec rake check:fast
bundle exec rake check:coverage
bundle exec rake check:crap
bundle exec rake check:audit
bundle exec rake test:package
```

Use `mise exec ruby@3.3.11 --` or `mise exec ruby@3.4.9 --` before the commands to select another installed Ruby.

Coverage manifests contain a run identifier, commit, lane, and hashes of all runtime sources. Old runs cannot satisfy the merge gate after sources change.

## Remaining acceptance gaps

Remote Linux results are recorded in the [CI and release workflow runs](https://github.com/svyatov/hawk.ruby/actions). Each release requires the complete CI matrix before publication.

Live Hawk ingestion and UI rendering are unverified. No dedicated live-test token was supplied or used.

Live acceptance must inspect backtraces, source snippets, users, context, breadcrumbs, severity, and grouping in a dedicated Hawk project.

Release association also requires deployment-time commit metadata uploaded with the same release identifier. Local collector tests do not verify that association.

The collector protocol and Ruby event routing were checked against Hawk's documentation and server sources. Live verification remains necessary before a production rollout.
