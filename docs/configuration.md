# Configuration

Configure the default client once, before requests or jobs begin. Reinitialization closes the previous default client.

```ruby
Hawk.init do |config|
  config.token = ENV.fetch("HAWK_TOKEN")
  config.environment = "production"
  config.enabled_environments = ["production", "staging"]
  config.source_roots = [File.expand_path("..", __dir__)]
  config.filter_parameters = ["session_id", /private_/i]
end
```

## Identity and capture policy

| Setting | Default | Meaning |
| --- | --- | --- |
| `token` | `ENV['HAWK_TOKEN']` | Hawk project integration token |
| `endpoint` | Derived HTTPS collector | Custom HTTPS endpoint; HTTP permits loopback IP literals only |
| `environment` | `RAILS_ENV`, `RACK_ENV`, or `development` | Event environment |
| `enabled_environments` | `nil` | All environments; an array restricts capture |
| `release` | `HAWK_RELEASE` or `REVISION` | Application revision attached to events |
| `detect_release` | `false` | Detect Git revision once during initialization, with a one-second deadline |
| `sample_rate` | `1.0` | Capture probability between zero and one |
| `ignored_exceptions` | `[]` | Exception ancestor names to exclude |
| `global_errors` | `true` | Capture uncaught main-process exceptions and drain at exit |
| `context`, `user` | `{}`, `nil` | Initial explicit context and user |

Automatic reporting excludes `SystemExit`, `SignalException`, and `Interrupt`. Manual exception capture remains available for those classes.

Automatic request reporting also excludes routing errors, missing actions, and missing Active Record records. Explicit `Rails.error.report` calls remain reportable.

## Delivery

| Setting | Default | Meaning |
| --- | --- | --- |
| `delivery_mode` | `:async` | Use one queue worker; `:sync` performs the attempt in the caller |
| `queue_capacity` | `100` | Maximum waiting events; a full queue rejects new captures |
| `connect_timeout` | `1.0` | Connection timeout in seconds |
| `read_timeout`, `write_timeout` | `2.0` | Socket timeouts in seconds |
| `flush_timeout` | `5.0` | Default flush and close deadline |
| `limit_cooldown` | `60.0` | Default cooldown after collector limits |

Each HTTP attempt has an additional five-second total deadline. Redirects and ambiguous transport failures are not retried.

Collector responses must contain a successful HTTP status of 200 and a JSON body with `code: 200` and `error: false`.

Responses with status 402 or 429 pause sends. Valid `Retry-After` seconds or dates are bounded to 300 seconds.

`Hawk.flush(timeout: 5.0)` waits for pending attempts. `Hawk.close(timeout: 5.0)` also stops accepting new events.

A false return means the operation could not finish within its contract. A true flush does not establish successful receipt by Hawk.

Forked children discard inherited queues and recreate synchronization before use. Parents retain their own queues. Abrupt termination can lose pending events.

## Scope and independent clients

Scopes are local to each client, thread, and fiber. `with_scope` copies current values and restores the parent scope after the block.

```ruby
Hawk.with_scope do |scope|
  scope.set_context(order_id: "order-42")
  scope.set_user(id: "customer-42")
  Hawk.capture_message("Order accepted")
end

configuration = Hawk::Configuration.new
configuration.token = ENV.fetch("OTHER_HAWK_TOKEN")
other = Hawk::Client.build(configuration)
other.capture_exception(RuntimeError.new("Independent project"))
other.close
```

Automatic request, channel, and job boundaries start fresh scopes. Explicit global configuration supplies their initial context.

Events receive an anonymous user identifier when no explicit identifier exists. That identifier is scoped to the execution and is not propagated to jobs.

Manual captures can repeat. Automatic captures suppress repeated propagation of the same exception object within one execution.

## Privacy and limits

| Setting | Default |
| --- | --- |
| `include_headers`, `include_cookies` | `false` |
| `include_request_body`, `include_job_arguments` | `false` |
| `propagate_job_context` | `true` |
| `filter_parameters` | `[]` |
| `send_source` | `true` |
| `source_roots` | `[Dir.pwd]` |

Built-in filtering covers sensitive key names, including passwords, secrets, authorization, API keys, and payment cards. Add application-specific names to `filter_parameters`.

Rails also applies `config.filter_parameters`. Opted-in raw bodies and cookie strings need explicit filtering or exclusion when their contents contain secrets.

The SDK uses parsed parameters already present in the request environment. It does not read or rewind the request input stream.

Source files must resolve inside a configured root. Source extraction excludes missing files, symlink escapes, nonregular files, and files over 1 MiB.

Events contain at most 100 backtrace frames, 10 causes, and 50 breadcrumbs. Source excerpts contain at most 11 lines.

JSON copying bounds depth, collection width, strings, and total nodes. It does not call application serializers or `inspect`.

Encoded events are limited to 256 KiB. Size reduction removes source snippets and optional detail before reducing backtraces. Events that remain oversized are dropped.

## Hooks and breadcrumbs

`before_send` receives detached, filtered event data without the integration token. Return a hash to send, or `nil` to drop.

`before_breadcrumb` receives a detached, filtered breadcrumb. Return a hash to retain it, or `nil` to drop.

```ruby
Hawk.init do |config|
  config.before_send = ->(event) { event.merge("title" => "Application failure") }
  config.before_breadcrumb = ->(entry) { entry }
  config.breadcrumbs_logger = true
  config.breadcrumbs_http = true
  config.logger_error_level = Logger::ERROR
end
```

Hook errors or invalid results drop only the affected event or breadcrumb. Hooks can add data, so their output needs the same privacy review as application logging.

Logger and Net::HTTP breadcrumbs require opt-in. Logger messages use normal Logger evaluation. HTTP breadcrumbs omit queries, credentials, headers, and bodies.

Rails notifications record operation names and timing. SQL text, bindings, mail content, and job arguments are excluded by default.

`breadcrumbs_rails` defaults to true with Rails. Set `logger_error_level` to convert qualifying logger messages into events; it defaults to disabled.

## Integration controls and diagnostics

Set entries in `integrations` to false to disable `:rails`, `:rack`, `:rake`, `:action_cable`, `:active_job`, `:sidekiq`, `:resque`, or `:delayed_job`.

`diagnostic_callback` receives counter snapshots. `diagnostic_logger` receives sanitized warning messages with the same counters.

```ruby
Hawk.init do |config|
  config.diagnostic_callback = ->(counts) { report_delivery_counters(counts) }
end

Hawk.client.diagnostics.snapshot
```

Counters include `sent`, `failed`, `overflow`, `filtered`, and `duplicate_overflow`. Only observed counters appear. Diagnostic failures do not replace application results.

## Releases

Set `HAWK_RELEASE` to the revision deployed with the application. Use the same identifier when uploading commit metadata through [Hawk's release uploader](https://github.com/codex-team/hawk.releases).

The uploader documents the `codex-team/hawk.releases@v1` action with `release` and `token` inputs. Run it during deployment.

[Hawk associates events and releases by matching release names](https://docs.hawk.so/releases). This gem attaches the identifier; deployment tooling uploads the commit metadata.
