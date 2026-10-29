# Hawk Ruby API

Hawk Ruby reports exceptions and messages to Hawk. Start with {Hawk} for the default client or {Hawk::Client} for independent project clients.

```ruby
require "hawk"

Hawk.init { |config| config.token = ENV.fetch("HAWK_TOKEN") }
Hawk.capture_message("Checkout completed", context: { order_id: "42" })
Hawk.close(timeout: 5.0)
```

Capture IDs confirm local acceptance. They do not confirm receipt by Hawk. Flush and close wait for delivery attempts, including failed attempts.

## Reference

- {Hawk::Configuration} documents settings, types, and defaults.
- {Hawk::Scope} holds context and user data for an execution.
- {Hawk::Diagnostics} exposes delivery and filtering counters.
- {Hawk::Rack} captures request and response-body exceptions.
- {Hawk::ConfigurationError} identifies invalid configuration.

See the {file:docs/configuration.md configuration guide} for privacy, delivery, and hook behavior. See the {file:docs/integrations.md integration guide} for Rails and background jobs.

Methods marked `@api private` support the implementation and are omitted from this reference. Their Ruby visibility does not make them supported extension points.
