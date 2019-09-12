# Changelog

This file documents the changes between releases of this library. When creating a pull request,
please at an entry to the "unreleased changes" section below.

### Unreleased changes

## Version 2.3.5

- Re-add `StatsD::Instrument.duration`, which was accidentally removed since verison 2.5.3 (#157)

## Version 2.3.4

- Improve performance of `Metric#to_s` (#152)
- Fix bug in escaping newlines for events with Datadog Backend (#153)

## Version 2.3.3

- Capture measure and distribution metrics on exception and early return (#134)

NOTE: Now that exceptions are measured statistics may behave differently. An exception example:
```
StatsD.measure('myhttpcall') do
  my_http_object.invoke
end
```
Version 2.3.2 and below did not track metrics whenever a HTTP Timeout exception was raised.
2.3.3 and above will include those metrics which may increase the values included.

A return example:
```
StatsD.measure('myexpensivecalculation') do
  return if expensive_calculation_disabled?
  expensive_calculation
end
```
If `expensive_calculation_disabled?` is true 50% of the time version 2.3.2 will drop the
average metric considerably.

## Version 2.3.2

- Add option to override global prefix for metrics (#148)

## Version 2.3.1

- Add mutex around UDP socket invalidation (#147)

### Version 2.3.0

- No changes from `beta6`, distribtions are GA at DataDog so making the distribution changes GA in gem

### Version 2.3.0.beta6

- Fix invalidate socket on connectivity issues in UDP (#135)

### Version 2.3.0.beta5

- Fixes bug in return value for blocks used in distributions (#132)

### Version 2.3.0.beta4

- Add support for distribution to accept a block
- Add class method for defining and removing a distribution from a method (same as a measure)
- Refactor most instrument methods to reduce code duplication

### Version 2.3.0.beta3

- fix for `:as_dist` parameter in the `statsd_measure` class method

### Version 2.3.0.beta2

- Add support for specifying a measure to emit as a distribution using `:as_dist` parameter

### Version 2.3.0.beta

- Add support for beta, datadog specifc distribution metrics
- Invalidate socket on connectivity issues

### Version 2.2.1

- Fix performance regression from v2.2.0

### Version 2.2.0

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
