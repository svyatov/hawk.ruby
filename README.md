# Hawk Ruby

Ruby error reporting for [Hawk](https://hawk.so), with optional Rails and background job integrations.

The gem reports exceptions, messages, backtraces, source snippets, breadcrumbs, users, context, and application releases. It uses Hawk's native collector format.

## Install

Version 0.1.0 is unreleased. Use this checkout with Bundler:

```ruby
gem "hawk-ruby", path: "../hawk.ruby", require: "hawk"
```

```sh
bundle install
```

To test a built artifact locally:

```sh
gem build hawk-ruby.gemspec
gem install ./hawk-ruby-0.1.0.gem
```

The core requires CRuby 3.3 or later and packaged standard libraries. Rails and job frameworks are optional.

## Configure and capture

Copy the integration token from your Hawk project into `HAWK_TOKEN`.

```ruby
require "hawk"

Hawk.init do |config|
  config.token = ENV.fetch("HAWK_TOKEN")
  config.release = ENV["HAWK_RELEASE"]
end

Hawk.set_context(component: "checkout")
Hawk.set_user(id: "customer-42")
Hawk.add_breadcrumb(message: "Payment started", category: "checkout")

Hawk.capture do
  perform_checkout
end

Hawk.capture_message("Checkout recovered", level: :warning)
Hawk.flush(timeout: 5.0)
```

`Hawk.capture` reports an escaping exception and raises the same exception again. You can also call `Hawk.capture_exception(error)` from a rescue handler.

A missing or empty token disables reporting. A malformed nonempty token raises `Hawk::ConfigurationError` during initialization.

## Rails and background jobs

Use `require: "hawk/rails"` in your Gemfile for Rails. Initialize Hawk in `config/initializers/hawk.rb` before workers start.

Rails enables request capture, `Rails.error`, Action Cable, Active Job, and safe notification breadcrumbs. Solid Queue works through Active Job.

Load each additional adapter explicitly:

```ruby
require "hawk/rack"
require "hawk/rake"
require "hawk/sidekiq"
require "hawk/resque"
require "hawk/delayed_job"
```

Rails also detects loaded job backends during initialization. The adapters preserve native retries, arguments, and failure storage.

See [integrations](docs/integrations.md) for placement, supported versions, propagation limits, and exclusions.

## Delivery and privacy

The default client uses one background thread and a queue of 100 events. Capture never waits for queue space. Each delivery makes one bounded HTTP attempt.

The queue is held in memory. An accepted capture ID confirms local acceptance. `flush` confirms that pending attempts finished, including failed attempts.

Request bodies, headers, cookies, and job arguments are excluded by default. Sensitive keys are filtered before hooks run. Review [configuration](docs/configuration.md) before enabling additional data.

Source snippets are enabled within configured source roots. Set `send_source = false` to exclude them.

## Development checks

```sh
bundle exec rake check:fast
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
