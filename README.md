# Hawk Ruby

Ruby error reporting for [Hawk](https://hawk.so), with optional Rails and background job integrations.

- Runs on CRuby 3.3 or later, with optional Rails and background job adapters.
- Built for Hawk: sends events directly to its native collector without a forwarding service.
- The default client bounds delivery to one background thread and a queue of 100 events.
- Excludes request bodies, headers, cookies, and job arguments by default.

## Install

Run this command from your application's directory, which must contain a Gemfile:

```sh
bundle add hawk-ruby --version "~> 0.1.2"
```

Copy the integration token from your Hawk project into `HAWK_TOKEN`. Save this example as `report.rb`:

```ruby
require "hawk-ruby"

Hawk.init do |config|
  config.token = ENV.fetch("HAWK_TOKEN")
end

Hawk.capture_message("Hello from Ruby") # => String capture ID when accepted
Hawk.flush(timeout: 5.0) # => true when pending delivery attempts finish
```

Run it with `bundle exec ruby report.rb`. A capture ID confirms local acceptance; it does not confirm receipt by Hawk.

## Configure and capture

After Hawk initialization, add this example to your application's `checkout.rb`:

```ruby
Hawk.set_context(component: "checkout")
Hawk.set_user(id: "customer-42")
Hawk.add_breadcrumb(message: "Payment started", category: "checkout")
Hawk.capture { raise "Checkout failed" } # raises RuntimeError after reporting
```

`Hawk.capture` reports an escaping exception and raises the same exception again. You can also call `Hawk.capture_exception(error)` from a rescue handler.

A missing or empty token disables reporting. A malformed nonempty token raises `Hawk::ConfigurationError` during initialization.

## Rails and background jobs

Use the standard Gemfile entry without a `require:` option. Initialize Hawk in `config/initializers/hawk.rb` before workers start:

```ruby
Hawk.init do |config|
  config.token = ENV.fetch("HAWK_TOKEN")
end
```

Rails enables request capture, `Rails.error`, Action Cable, Active Job, and safe notification breadcrumbs. Solid Queue works through Active Job.

Hawk automatically detects loaded Rails, Rake, Sidekiq, Resque, and Delayed Job integrations during startup. Load application dependencies before calling `Hawk.init`. No adapter requires are needed.

For a standalone Rack application, add `use Hawk::Rack` to `config.ru`. Rails inserts this middleware automatically. The adapters preserve native retries, arguments, and failure storage.

See [integrations](docs/integrations.md) for placement, supported versions, propagation limits, and exclusions.

See [configuration](docs/configuration.md) for settings and [API documentation](CONTRIBUTING.md#api-documentation) to build the YARD reference.

## Delivery and privacy

The default client uses one background thread and a queue of 100 events. Capture never waits for queue space. Each delivery makes one bounded HTTP attempt.

The queue is held in memory. An accepted capture ID confirms local acceptance. `flush` confirms that pending attempts finished, including failed attempts.

Request bodies, headers, cookies, and job arguments are excluded by default. Sensitive keys are filtered before hooks run. Review [configuration](docs/configuration.md) before enabling additional data.

Source snippets are enabled within configured source roots. Set `send_source = false` to exclude them.

## Development checks

```sh
bundle exec rake check:fast
bundle exec rake check:docs
bundle exec rake check:coverage
bundle exec rake check:crap
bundle exec rake check:audit
bundle exec rake test:package
```

Coverage runs the 13 compatibility lanes for the current Ruby. Install their bundles first with `bundle install --gemfile gemfiles/NAME.gemfile`.

The CI workflow defines 39 runtime combinations across Ruby 3.3, 3.4, and 4.0. It enforces complete types, 100% line and branch coverage, and measured CRAP scores at most 10.

Use `bundle exec rake check:complexity` for local complexity feedback without coverage. See [verification](docs/verification.md) for observed results and remaining acceptance gaps.

## License

MIT. See [LICENSE](LICENSE).

## Help and maintenance

Leonid Svyatov maintains Hawk Ruby. Use [GitHub issues](https://github.com/svyatov/hawk.ruby/issues) for questions and defect reports.

Read the [changelog](CHANGELOG.md) for releases and the [contributing guide](CONTRIBUTING.md) to propose a change.
