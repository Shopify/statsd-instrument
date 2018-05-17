# Changelog

This file documents the changes between releases of this library. When creating a pull request,
please at an entry to the "unreleased changes" section below.

### Unreleased changes

- Add support for two new datadog specific metric types: events and service checks.

### Version 2.1.3

- The `assert_statsd_calls` test helper will now raise an exception whenever a block isn't passed.
- Sending stats inside an exit handler will no longer cause programs to exit abruptly.

### Version 2.1.2

- Use `prepend` instead of rewriting classes for metaprogramming methods.
- RSpec: make matchers more flexible.
- Bugfix: Only ask Rails for the environment when it's actually loaded.

### Version 2.1.1

- Add `assert_statsd_calls` to from validating cases where one has multiple metrics with the same name and type being recorded, but with different options.

### Version 2.1.0

- Fix rspec-rails compatibility
- Add `value` keyword argument to all metric types.

### Version 2.0.12

- Make StatsD client thread-safe
- Assertions: Ensure sample rates have proper values.
- Assertions: Make tag assertions work more intuitively
- RSpec: Add backwards compatibility for RSpec 2

### Version 2.0.11

- Don't change method visibility when adding instrumentation to methods using metaprogramming
- RSpec: add support for Compound expectations

### Version 2.0.10

- Assertions: allow ignoring certain tags when asserting for other tags to be present.

### Version 2.0.9

- Better error message for `assert_no_statsd_calls`

### Version 2.0.8

- More tag handling performance improvements.
- RSpec matchers documentation improvements

### Version 2.0.7

- Tag handling performance improvements.
- Test against Ruby 2.2.
- Drop support for Ruby 1.9.3.

### Version 2.0.6

- Fix some loading order issues in Rails environments.
- Default behavior: in a **staging** environment, the defaults are now the same as in a **production environment**.
- Documentation overhaul

### Version 2.0.5

- Allow for nested assertions using the `assert_statsd_*` assertion methods.

### Version 2.0.4

- Add a Railtie to fix some initialization issues.

### Version 2.0.3

- Assertion method bugfixes

### Version 2.0.2

- Documentation fixes

### Version 2.0.1

- Add assertion methods `assert_statsd_histogram`, `assert_statsd_set`, and `assert_statsd_key_value`.

### Version 2.0.0

- Complete rewrite using pluggable backends.
- Add assertion methods in `StatsD::Instrument::Assertions` to make testing easier and less brittle.
- Drop support for Ruby 1.8
