# Hawk Ruby catcher design

Status: approved by the user on 2026-10-29.

## Intent and agreed scope

Build one Ruby gem that reports application errors to Hawk through its native collector protocol.
The core works without Rails. Optional integrations provide Sentry-style error coverage for Rails and background jobs.

The user selected O1, one gem with optional integrations.
The user also requires RuboCop, Steep, full type coverage, `crap4ruby`, and useful code quality checks.
The user explicitly requested installing the latest `crap4ruby` release during design.

This is a full project, including packaging, transport, concurrency, framework adapters, documentation, and continuous integration.
The repository starts without files or commits.

## Goals

- G1: Capture Ruby errors manually and at supported automatic capture boundaries.
- G2: Cover Rack, Rails requests, `Rails.error`, Action Cable, Active Job, Sidekiq, Resque, and Delayed Job.
- G3: Send source snippets, breadcrumbs, context, users, runtime metadata, and application releases in Hawk-compatible fields.
- G4: Preserve application exceptions, exit behavior, job retries, and request handling when reporting fails.
- G5: Check every shipped Ruby implementation file with Steep and ship complete RBS signatures.

## Non-goals and limits

Sentry API compatibility, tracing, profiling, metric ingestion, cron check-ins, session replay, and standalone log ingestion are outside this error-reporting scope.
Logs can supply breadcrumbs and explicitly configured error events.
Hawk grouping, notifications, assignments, and retention remain server responsibilities.

Automatic capture applies after initialization and integration activation.
The gem cannot guarantee reporting after `SIGKILL`, interpreter crashes, exhausted memory, or lost process state.
Arbitrarily rescued exceptions require manual reporting or a supported framework reporting hook.
Arbitrary application threads require an explicit capture wrapper unless their error terminates the main process.
Do not use a process-wide `TracePoint` to report every raised exception.

Local variable extraction is excluded because Ruby exceptions do not retain the required frame bindings.
Cause chains remain available as structured addons, without promising a dedicated Hawk cause-chain interface.

## Approaches

| Code | Approach | Trade-off | Decision |
| --- | --- | --- | --- |
| O1 | One gem with separately loaded adapters | One release cycle; adapters need a shared compatibility matrix | Selected by the user |
| O2 | Separate core and integration gems | Independent dependencies and releases; more publishing and compatibility work | Rejected |

Use the native Hawk protocol with `catcherType: errors/ruby`.
The collector routes unknown catcher types to its generic error worker.
The generic worker preserves the original catcher type.
Hawk's interface derives source language from that type and renders arbitrary addons as JSON.

No Hawk server changes are required by this design.
Source inspection establishes compatibility expectations; a live end-to-end test must confirm the deployed service.

## Proposed implementation decisions

These author proposals were accepted with approval of this document.

| Decision | Proposal |
| --- | --- |
| Package | `hawk-ruby`, namespace `Hawk`, initial version `0.1.0`; check name availability before publication |
| Ruby | CRuby 3.3, 3.4, and 4.0 |
| Rails | Rails 7.2, 8.0, and 8.1, on valid Ruby combinations |
| Other adapters | Rack 2 and 3; Sidekiq 7 and 8; Resque 2; Delayed Job 4 |
| Tests | Minitest, real framework fixtures, and local HTTP collector fixtures |
| Runtime | Ruby standard libraries; declare packaged standard-library dependencies where Ruby requires them |
| License | MIT for original code; do not copy upstream SDK implementation code |

Dependency resolution must confirm supported combinations before implementation claims compatibility.
The implementation plan must record exact tested versions and upstream requirements.
An incompatible combination requires an explicit design amendment, not a silent reduction of coverage.

## Components and public interface

The core contains configuration, client, execution scope, event construction, source extraction, filtering, and HTTP delivery.
Adapters translate framework callbacks into the same client interface.
Keep framework constants and dependencies out of the standalone loading path.

Expose `Hawk.init`, `Hawk.capture_exception`, `Hawk.capture_message`, `Hawk.with_scope`, `Hawk.set_user`, and `Hawk.set_context`.
Expose `Hawk.add_breadcrumb`, `Hawk.flush`, `Hawk.close`, and `Hawk.capture` as a block wrapper that reports and re-raises.
Allow independent client instances for applications using several Hawk projects.
The module delegates to a default client.

Configuration includes token, endpoint override, environment, release, enabled environments, source roots, ignored exceptions, sampling, and integration switches.
It also includes delivery mode, queue limits, timeouts, filtering hooks, and a diagnostic logger.
Validate configuration during initialization. Missing tokens disable reporting; malformed supplied tokens raise a configuration error.
Loading the gem alone installs no handlers and sends no requests.

Capture methods return a local event identifier when accepted for delivery and `nil` when disabled, filtered, sampled, or rejected.
This identifier is diagnostic metadata, not a Hawk server event identifier or delivery receipt.
`flush` returns whether pending delivery completed within its deadline; completion does not imply successful ingestion.
`close` stops acceptance and drains within its deadline. Later captures return `nil` until reinitialization.
Reinitialization closes the previous client and avoids registering duplicate integration hooks.

## Event contract

Send a JSON object with `token`, `catcherType`, and `payload`.
Decode the integration token as Base64 JSON containing `integrationId` and `secret`.
Validate identifier syntax before using it as a DNS label.
Derive `https://<integrationId>.k1.hawk.so` using standard HTTPS port 443.
The documentation's port 433 conflicts with the Python SDK and is not used.
Custom endpoints support HTTPS; explicitly configured loopback HTTP supports local testing.
Do not follow HTTP redirects carrying the integration token.

| Hawk field | Ruby mapping |
| --- | --- |
| `title` | Exception message or explicit message |
| `type` | Exception class, or `Message` for explicit messages |
| `backtrace` | Newest frame first, with file, line, function, and available source snippets |
| `breadcrumbs` | Bounded entries with Unix timestamps in milliseconds |
| `release` | Configured application revision, optionally detected once from deployment metadata or Git |
| `user` | Explicit user fields, or an anonymous identifier within a defined execution boundary |
| `context` | Global, scoped, and event context, merged with event values taking precedence |
| `catcherVersion` | Gem version |
| `addons` | Ruby runtime, environment, local event ID, severity, capture mechanism, request, job, and cause-chain data |

Context merging is shallow and uses normalized string keys.
Nested objects are replaced by the more specific value.
User values follow event, scope, then configuration precedence.
Normalize arbitrary boundary values to a bounded JSON representation without modifying application objects.
Handle invalid encodings, cycles, excessive depth, unsupported objects, and failures in user-defined conversions.

Use `Exception#backtrace_locations` when present, with a string-backtrace fallback.
Read source only from configured real paths, with symlink resolution, file-size limits, and regular-file checks.
Missing files and malformed frames never prevent the rest of an event from being sent.
Proposed limits: 100 frames, five source lines on each side, ten causes, 50 breadcrumbs, and 256 KiB per encoded event.
Trim optional data before dropping an oversized event. Preserve title and available top-frame information.
The implementation plan defines a deterministic trimming order and string/depth limits.

Send severity in addons because Hawk's documentation and shared event type disagree about a top-level severity field.
Do not promise severity-based Hawk filtering without a verified server contract.
Do not send the optional repetition `count`; the inspected collector envelope does not preserve it.

## Execution scopes and duplicate prevention

Use execution-local state that isolates fibers and threads.
Each request, Action Cable invocation, and job execution receives a fresh scope, restored in an ensure block.
Nested scopes inherit snapshots. Event construction snapshots data before asynchronous delivery.

Framework jobs may inherit explicitly set user and context through bounded, filtered metadata at enqueue time.
Automatic request data and breadcrumbs do not cross into jobs by default.
Provide an option to disable propagation. Do not alter job arguments or retry semantics.
Use adapter-supported metadata where available; the plan must specify each backend's serialization mechanism and round-trip tests.

When no explicit user exists, create an anonymous identifier for the execution scope.
Standalone scripts use a client-local anonymous identifier.
Do not claim these identifiers measure distinct people across separate requests or executions.
Applications needing that measurement must supply a stable user ID.

Track automatic reporting of the same exception object within one execution boundary.
Rack, Rails, and backend adapters must not send the same failure twice.
Clear duplicate state between retry attempts so each failed attempt remains reportable.
Repeated explicit manual captures remain intentional reports.
Use bounded scope state, without permanent exception registries or application-object mutation.

## Automatic capture coverage

| Boundary | Behavior |
| --- | --- |
| Standalone process | An enabled shutdown hook reports the uncaught main exception and drains delivery without changing exit status |
| Explicit block wrapper | Reports escaping exceptions and re-raises the original exception |
| Rack | Middleware reports escaping application exceptions and restores the request scope |
| Rails requests | Railtie installs middleware and framework hooks, covering exceptions processed by Rails exception rendering |
| `Rails.error` | Subscriber reports explicit framework reports, preserving handled status, severity, source, and supplied context |
| Action Cable | Reports failed channel callbacks and connection operations through framework hooks, preserving normal handling |
| Active Job | Reports escaping execution errors and terminal retry/discard failures; supported backends retain native retry behavior |
| Sidekiq | Server hooks cover direct jobs and framework jobs, with one report per failed attempt |
| Resque | Failure hooks cover direct jobs and forked execution, with bounded delivery before worker exit |
| Delayed Job | Plugin hooks cover direct jobs and framework jobs, preserving backend retries |
| Rake | Optional task wrapper reports escaping task failures and re-raises |

Rails integration activates when Rails loads the gem through Bundler.
Provide explicit require paths for Rails, Rack, and each job adapter, including use outside Rails.
Adapters activate only when their framework exists and the integration is enabled.
Use official extension points. Any necessary method wrapping must be narrow, version-bounded, and tested against real frameworks.

Active Job support includes Solid Queue through its Active Job integration.
Test job deserialization failures through backend failure hooks where those hooks expose them.
Infrastructure failures without a job exception require the backend's error hook or explicit reporting.
Jobs handled by application `rescue_from` callbacks require an explicit report unless Rails reports them.

Default exclusions omit expected Rack/Rails routing and missing-record errors and normal process termination.
`Rails.error` reports explicitly supplied by the application remain eligible unless an explicit ignore rule matches.
The plan must enumerate defaults, including how explicit reports override framework-only exclusions.

## Breadcrumbs and privacy

Support manual breadcrumbs and configurable automatic breadcrumbs from Rails notifications, standard logging, and `Net::HTTP`.
Rails notifications cover controller actions, database operations, mail delivery, and job lifecycle events.
Record operation names and timings by default. SQL text, query bindings, bodies, cookies, and credentials remain excluded by default.
Automatic HTTP breadcrumbs contain method, host, path, status, and duration, with query values removed.
Exclude Hawk's own transport and diagnostics from instrumentation.
Allow users to disable categories and filter or drop breadcrumbs before storage.

Apply recursive sensitive-key filtering and Rails parameter filters before delivery.
Authorization headers, session cookies, raw request bodies, and job arguments require explicit opt-in.
Source collection can be disabled independently. Source snippets can contain secrets and must be covered by `before_send`.
User identity is explicit or anonymous; never infer authenticated identity through application-specific methods.

`before_send` receives a detached event payload after built-in filtering and normalization.
It returns a replacement payload or `nil`/`false` to discard the event.
A raised hook error or invalid result discards the event and produces a bounded diagnostic.
Validate and size-limit the replacement before sending; never fall back to the original unsanitized data.
Diagnostics contain no integration token, raw event payload, or collector response body.

## Transport and lifecycle

Use a bounded in-process queue and one delivery worker by default.
Provide synchronous delivery for scripts, tests, and integrations requiring delivery before process exit.
Proposed defaults: 100 queued events, one-second connection timeout, two-second read/write timeouts, and a five-second flush deadline.
Capture never waits for queue capacity. Drop the newest event when full and record a diagnostic counter.
An optional diagnostic callback exposes sent, failed, filtered, and overflow counts.

Read HTTP status and Hawk's JSON response, including its error flag.
HTTP success means collector acceptance, not successful grouping or display.
Honor supported `Retry-After` responses with a bounded cooldown; discard events during cooldown rather than accumulating retries.
Treat Hawk's 402 limit response as a delivery failure with a configurable cooldown.
Do not automatically resend ambiguous requests: Hawk provides no verified idempotency contract.
Durable delivery and exactly-once ingestion are not guaranteed.

Workers detect process-ID changes and recreate threads, queues, and network state after fork.
Children never resend the parent's queued events.
Resque child hooks flush their own events before exit.
Normal shutdown drains only within its deadline.
Never change signal handlers, process exit status, or exception propagation to make delivery succeed.

## Releases and suspected commits

Attach an application release to each event when configured.
Document Hawk's release uploader for sending commit metadata during deployment.
Use the same release identifier for both uploads and events.
Do not run Git or upload commit history on the exception path.
A deployment-time Ruby release uploader is outside this gem's first implementation scope because Hawk already supplies an uploader.

## Quality gates

| Check | Requirement |
| --- | --- |
| RuboCop | All project Ruby, gemspecs, Rake tasks, and tests pass; no generated blanket suppression file |
| Steep | Every shipped Ruby file is checked; all public and private methods have precise signatures |
| RBS | Validate and package signatures; include narrow framework interfaces and dependency signatures |
| Type coverage | Parse Steep statistics; require zero untyped calls, successful rows, and coverage of every shipped Ruby file |
| Boundary types | No `untyped` escape hatches, blanket ignores, or unchecked casts used to satisfy coverage |
| Tests | Unit, HTTP contract, subprocess, concurrency, fork, and real integration tests pass |
| Test coverage | SimpleCov tracks every runtime file, including adapters; require 100% line and branch coverage across merged suites |
| CRAP | `crap4ruby` measures every library method against fresh SimpleCov data; require a score at most 10 |
| Dependency security | `bundler-audit` checks development and integration lockfiles against an updated advisory database |
| Packaging | Build the gem and test installed artifacts, optional loading, and bundled RBS signatures |

Full type coverage means all shipped implementation files and their call sites, including adapters.
It does not claim third-party Ruby code is fully typed.
Tests must validate framework signature assumptions and boundary normalization.
Statistics alone are insufficient: reject missing files, failed analyses, and signatures hiding dynamic calls.

Use Minitest for behavioral checks and SimpleCov for coverage. Both are development dependencies.
RuboCop, Steep, RBS, `crap4ruby`, and `bundler-audit` also remain development dependencies.
Resolve compatible released versions after checking upstream installation instructions.
Do not add overlapping style tools or Rails-application scanners without a specific uncovered need.

Provide a fast local check for lint, types, and core behavior.
Run the full framework matrix and merged coverage in continuous integration.
Run `bundle exec crap4ruby lib --coverage coverage/.resultset.json --threshold 10` after the coverage suites, without rerunning tests.
Discard previous resultsets before collecting coverage. Merge only reports from the same source revision, with normalized source paths.
Require measurable scores for method bodies. Avoid inline definitions whose coverage cannot be measured by `crap4ruby`.
The local complexity signal uses `bundle exec crap4ruby lib --no-coverage --no-save`, without claiming measured CRAP enforcement.
Keep normal tests independent of Hawk credentials, Redis, and a production network.
Backend contract tests may use isolated local Redis and database services in dedicated integration jobs.
GitHub workflows run these gates on pull requests. Publication remains a separate, explicitly requested action.

## Verification and acceptance

1. V1: Install the built gem in a plain Ruby fixture and send exceptions and messages to a local collector fixture.
2. V2: Trigger Rails request, error-reporter, and Action Cable failures, then inspect exact payloads and exception behavior.
3. V3: Trigger direct and Active Job failures across supported backends, including retries, discards, deserialization, and forked workers.
4. V4: Prove scope isolation, enqueue propagation, duplicate prevention, filtering, source restrictions, and failure handling under concurrency.
5. V5: Pass quality gates, then inspect a bounded live test in Hawk when a dedicated project token is available.

Transport tests cover invalid tokens, rejected authentication, malformed replies, oversized events, timeouts, queue overflow, cooldowns, and shutdown deadlines.
Subprocess tests verify original exit codes, fork behavior, and absence of duplicate shutdown reports.
Type gates include deliberate missing-file and untyped-call failures to prove enforcement.

Live acceptance must inspect the received backtrace, source snippets, context, addons, user, breadcrumbs, and release in Hawk's interface.
Release verification needs commit metadata uploaded for the matching release.
Without live credentials, report local and source-level evidence separately and leave live acceptance explicitly unverified.

## Work left to the implementation plan

The builder chooses internal class names, test layouts, exact released dependency versions, and valid matrix combinations within the proposed support ranges.
The plan must pin tested framework contracts, define adapter metadata formats, and enumerate filtering and exclusion defaults.
It must specify source limits, payload trimming, integration activation order, and the type-coverage enforcement mechanism.
No product code or framework scaffolding starts before this design is approved.
Dependency installation also waits, except the user's explicit request to install `crap4ruby` during design.
Version 0.2.1 is the verified published release selected for that installation.

## Sources inspected

Protocol and behavior were inspected on 2026-10-29. Branch links may change.

- [Hawk documentation](https://docs.hawk.so/integrations), including every section linked in its navigation.
- [Catcher requirements](https://docs.hawk.so/how-to-create-a-catcher), [event format](https://docs.hawk.so/event-format), and [credentials](https://docs.hawk.so/endpoint-and-credentials).
- [Filtering](https://docs.hawk.so/sensitive-data-filtering) and [releases](https://docs.hawk.so/releases).
- [Python implementation](https://github.com/codex-team/hawk.python/blob/master/src/hawk_python_sdk/core.py), including Flask and FastAPI documentation.
- [Node.js documentation](https://github.com/codex-team/hawk.nodejs) and [Laravel documentation](https://github.com/codex-team/hawk.laravel).
- [Collector dispatch](https://github.com/codex-team/hawk.collector/blob/master/pkg/server/errorshandler/handler.go) and [message envelope](https://github.com/codex-team/hawk.collector/blob/master/pkg/server/errorshandler/messages.go).
- [Generic worker](https://github.com/codex-team/hawk.workers/blob/master/workers/default/src/index.ts).
- [Shared event type](https://github.com/codex-team/hawk.types/blob/master/src/base/event/event.ts) and [catcher types](https://github.com/codex-team/hawk.types/blob/master/src/catchers/catcher-message.ts).
- [Event interface](https://github.com/codex-team/hawk.garage/blob/master/src/components/event/Overview.vue) and [addon rendering](https://github.com/codex-team/hawk.garage/blob/master/src/components/event/details/DetailsAddons.vue).
- [Release uploader](https://github.com/codex-team/hawk.releases).
- [Sentry Rails documentation](https://docs.sentry.io/platforms/ruby/guides/rails/) and [Ruby integration source tree](https://github.com/getsentry/sentry-ruby).
- [RuboCop](https://github.com/rubocop/rubocop), [Steep](https://github.com/soutaro/steep), and [RBS](https://github.com/ruby/rbs).
- [Steep statistics implementation](https://github.com/soutaro/steep/blob/master/lib/steep/drivers/stats.rb).
- [SimpleCov](https://github.com/simplecov-ruby/simplecov) and [bundler-audit](https://github.com/rubysec/bundler-audit).
- [Minitest](https://github.com/minitest/minitest) and [crap4ruby](https://github.com/svyatov/crap4ruby).
- [crap4ruby 0.2.1 release](https://github.com/svyatov/crap4ruby/releases/tag/v0.2.1), matched against RubyGems metadata before installation.
