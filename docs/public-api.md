# Public API and compatibility

Hawk Ruby uses [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) for the interfaces described here.

## Supported interfaces

The public API includes:

- The `Hawk` methods documented in the [README](../README.md): initialization, capture, context, user, breadcrumbs, scopes, flushing, and closing.
- Configuration settings, hooks, diagnostics counters, and lifecycle behavior documented in [configuration](configuration.md).
- Independent clients created with `Hawk::Configuration.new` and `Hawk::Client.build`, using the capture, context, scope, flush, and close methods documented there.
- `Hawk::Scope#set_context` and `Hawk::Scope#set_user` inside a `with_scope` block.
- The `Hawk::ConfigurationError` exception for invalid configuration.
- Require paths, supported runtime and framework versions, and adapter behavior documented in [integrations](integrations.md).
- The documented job-context format and its producer/consumer compatibility requirements.

Other classes, helper methods, internal event construction, and the exact text of error or diagnostic messages are implementation details. Their presence in Ruby signatures does not make them supported interfaces.

## Version increments

Before version 1.0.0, incompatible public API changes increment the minor version. Compatible additions and fixes increment the patch version.

From version 1.0.0, incompatible changes increment the major version. Compatible additions and deprecations increment the minor version; compatible fixes increment the patch version.

Raising the minimum supported Ruby or framework version is an incompatible change.

## Deprecation and removal

A public interface remains usable for at least one released version after its deprecation. The notice names its replacement or migration path and earliest removal version.

Deprecations appear in the changelog and through the affected interface when a runtime notice can reach the caller without exposing private data.

Before 1.0.0, removal waits for a later minor release. From 1.0.0, deprecation ships in a minor release and removal waits for a later major release.
