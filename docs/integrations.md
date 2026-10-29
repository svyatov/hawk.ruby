# Integrations

Load optional adapters before workers start. Keep their framework gems in the application's Gemfile.

## Supported versions

| Component | Tested versions |
| --- | --- |
| CRuby | 3.3.11, 3.4.9, 4.0.9 |
| Rails, Active Job, Action Cable | 7.2.4, 8.0.5.1, 8.1.4 |
| Rack | 2.2.24, 3.2.7 |
| Sidekiq | 7.3.10, 8.1.7 |
| Resque | 2.7.0 |
| Delayed Job, Active Record backend | 4.2.0, 4.1.11 |
| Solid Queue | 1.7.0 |
| Rake | 13.4.2 |

Sidekiq 8.1.7 and Rails 7.2.4 cannot share a bundle: their `connection_pool` requirements conflict. Sidekiq 7 runs with Rails 7.2 and 8.1.

The adapters guard their supported framework versions. Resque activation requires version 2.7.0. The core uses normal RubyGems or Bundler activation.

## Rack

```ruby
require "hawk/rack"

Hawk.init { |config| config.token = ENV.fetch("HAWK_TOKEN") }
use Hawk::Rack
run Application.new
```

Place Hawk inside middleware that consumes application exceptions. It must receive the escaping error to report it.

The middleware retains request scope through response iteration, callable streaming bodies, and close. File bodies retain their `to_path` protocol.

Request metadata includes method, path, available parsed parameters, request ID, controller, and action. Raw query strings and request input streams are excluded.

Use `Hawk::Rack.new(app, client: other_client)` for an independent project client.

## Rails requests and framework reports

Use `require: "hawk/rails"` in your Gemfile. The Railtie inserts Hawk inside `ActionDispatch::DebugExceptions`.

```ruby
# config/initializers/hawk.rb
Hawk.init do |config|
  config.token = ENV.fetch("HAWK_TOKEN")
  config.environment = Rails.env
  config.release = ENV["HAWK_RELEASE"]
end
```

If Rails is already loaded, requiring `hawk` also discovers its Railtie. Rails filtering runs before the application's `before_send` hook.

The subscriber records explicit `Rails.error.report` calls, including handled errors and severity. Request dispatch reports share ownership with middleware to prevent duplicates.

Automatic requests exclude `ActionController::RoutingError`, `AbstractController::ActionNotFound`, `ActionController::UnknownAction`, and `ActiveRecord::RecordNotFound`.

Explicit framework reports and manual captures can still report those exceptions.

## Action Cable

The Rails adapter wraps channel actions, subscription changes, and connection open and close operations. Each invocation receives a fresh scope.

Application rescue handlers keep their normal return values and behavior. Hawk observes errors consumed by Cable's handler path.

Metadata includes the channel or connection class and operation. Message bodies and inferred application identities are excluded.

## Active Job and Solid Queue

Rails activates the Active Job adapter. It covers direct execution, backend execution, deserialization errors, terminal discards, and exhausted retries.

Native retry schedules and application rescue handlers remain unchanged. Intermediate handled retries generate events only when Rails explicitly reports them.

```ruby
Hawk.with_scope do
  Hawk.set_context(section: "checkout")
  Hawk.set_user(id: "customer-42")
  ReceiptJob.perform_later("order-42")
end
```

The serialized job receives a separate `hawk` field containing versioned explicit context and user data. Job arguments remain unchanged.

Metadata is filtered, JSON-only, and limited to 8 KiB. Malformed, oversized, or unknown-version metadata is ignored.

Version 1 metadata is filtered by its producer. Consumers preserve that state, including when a job enqueues another job. Use the same custom Rails privacy filters on producers and consumers; a consumer-only filter change does not transform previously queued values. New explicit scope values and event overrides receive filtering normally.

Automatic request metadata, breadcrumbs, and anonymous users are not propagated. Set `propagate_job_context = false` to disable propagation.

Solid Queue uses this same Active Job contract. Tests exercise its database-backed claim and execution paths.

## Sidekiq

```ruby
require "hawk/sidekiq"
```

Client middleware adds versioned context under a separate top-level `hawk` field. Server middleware starts an execution scope.

The backend handler covers failures before server middleware. A failed native attempt produces one automatic event across both paths.

Each failed retry attempt is independently reportable. Active Job retries that Rails handles internally follow the Active Job policy.

The adapter retains native payload arguments and retry behavior. Raw arguments require `include_job_arguments = true`.

## Resque

```ruby
require "hawk/resque"
```

The adapter wraps job execution and delegates failure creation to the configured backend. Failed constantization and other failures before execution reach that backend path.

Forked children reset inherited delivery state and flush their own events before Resque exits. A parent does not resend its queued events from a child.

Direct Resque arguments and queue payloads remain unchanged. Direct jobs start fresh explicit scopes because this adapter adds no arbitrary queue metadata.

Active Job wrappers retain their own serialized context. Raw direct arguments require opt-in.

## Delayed Job

```ruby
require "hawk/delayed_job"
```

Load the adapter before starting a worker. Its plugin observes perform, error, and failure callbacks, including handler deserialization failures.

Native attempts, retry times, and terminal failure state remain unchanged. Direct job YAML and database columns remain unchanged.

Active Job wrappers carry their own versioned context. Direct jobs start fresh scopes without adding attributes to application payload objects.

## Rake and process shutdown

```ruby
require "hawk/rake"
```

The Rake adapter reports escaping task failures and retains original task behavior. Nested task failures share automatic-report ownership.

Core initialization installs one process exit hook when `global_errors` is enabled. It reports eligible uncaught main-process errors and attempts a bounded drain.

Handled application errors require an explicit capture. For independently managed clients, call `close` during application shutdown.

## Scope of this SDK

This SDK implements Hawk error reporting. Tracing, profiling, metrics, cron monitoring, and standalone log ingestion are outside its scope.

Delivery uses an in-memory queue and one attempt per event. Job backends own retries. Use delivery counters to distinguish accepted captures from successful collector responses.
