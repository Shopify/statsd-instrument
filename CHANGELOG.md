# Changelog

This file documents the changes between releases of this library. When
creating a pull request, please add an entry to the "unreleased changes"
section below.

### Unreleased changes

- Slight behaviour change when using the `assert_statsd_*` assertion methods in
  combination with `assert_raises`: we now do not allow the block passed to the
  `assert_statsd_` call to raise an exception. This may cause tests to fail that
  previousloy were succeeding.

  Consider the following example:

  ``` ruby
  assert_raises(RuntimeError)
    assert_statsd_increment('foo') do
      raise 'something unexpected'
    end
  end
  ```

  In versions before 2.3.3, the assert `assert_statsd_*` calls would silently
  pass when an exception would occur, which would later be handled by
  `assert_raises`. So the test would pass, even though no `foo` metric would be
  emitted.

  Version 2.3.3 changed this by failing the test because no metric was being
  emitted. However, this would hide the the exception from the assertion message,
  complicating debugging efforts.

  Now, we fail the test because an unexpected exception occured inside the block.
  This means that the following test will fail:

  ``` ruby
  assert_raises(RuntimeError)
    assert_statsd_increment('foo') do
      StatsD.increment('foo')
      raise 'something unexpected'
    end
  end
  ```

  To fix, you will need to nest the `assert_raises` inside the block passed to
  `assert_statsd_instrument` so that `assert_statsd_increment` will not see any
  exceptions:

  ``` ruby
  assert_statsd_increment('foo') do
    assert_raises(RuntimeError)
      StatsD.increment('foo')
      raise 'something unexpected'
    end
  end
  ```

  See #193, #184, and #166 for more information.


## Version 2.5.0

- **DEPRECATION**: Providing a sample rate and tags to your metrics and method
  instrumentation macros should be done using keyword arguments rather than
  positional arguments. Also, previously you could provide `value` as a keyword
  argument, but it should be provided as the second positional argument.

  ``` ruby
  # DEPRECATED
  StatsD.increment 'counter', 1, 0.1, ['tag']
  StatsD.increment 'counter', value: 123, tags: { foo: 'bar' }
  StatsD.measure('duration', nil, 1.0) { foo }
  statsd_count_success :method, 'metric-name', 0.1

  # SUPPORTED
  StatsD.increment 'counter', sample_rate: 0.1, tags: ['tag']
  StatsD.increment 'counter', 123, tags: { foo: 'bar' }
  StatsD.measure('duration', sample_rate: 1.0) { foo }
  statsd_count_success :method, 'metric-name', sample_rate: 0.1
  ```

  The documentation of the methods has been updated to reflect this change.
  The behavior of the library is not changed for the time being, so you can
  safely upgrade to this version. However, in a future major release, we will
  remove support for the positional arguments.

  The library includes some cops to help with finding issues in your existing
  codebase, and fixing them:

  ``` sh
  # Check for positional arguments on your StatsD.metric calls
  rubocop --only StatsD/PositionalArguments \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/positional_arguments.rb

  # Check for positional arguments on your statsd_instrumentation macros
  rubocop --only StatsD/MetaprogrammingPositionalArguments \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/metaprogramming_positional_arguments.rb

  # Check for value as keyword argument
  rubocop --only StatsD/MetricValueKeywordArgument \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/metric_value_keyword_argument.rb

  ```

- **DEPRECATION**: Relying on the return value of the StatsD metric methods
  (e.g. `StatsD.increment`) is deprecated. StatsD is a fire-and-forget
  protocol, so your code should not depend on the return value of these methods.

  The documentation of the methods has been updated to reflect this change.
  The behavior of the library is not changed for the time being, so you can
  safely upgrade to this version. However, in a future major release, we will
  start to explicitly return `nil`.

  This gem comes with a Rubocop rule that can help verify that your
  application is not relying on the return value of the metric methods. To use
  this cop on your codebase, invoke Rubocop with the following arguments:

  ``` sh
  rubocop --only StatsD/MetricReturnValue \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/metric_return_value.rb
  ```

- **Strict mode**: These custom Rubocop rules will give you a quick indication
  of the issues in your codebase, but are not airtight. This library now also
  ships with strict mode, a mixin module that already disables this deprecated
  behavior so it will raise exceptions if you are depending on deprecated
  behavior. It will also do additional input validation, and make sure the
  `StatsD` metric methods return `nil`.

  You enable strict mode by requiring `statsd/instrument/strict`:

  ``` ruby
  # In your Gemfile
  gem 'statd-instrument', require: 'statsd/instrument/strict'

  # Or, in your test helper:
  require 'statsd/instrument/strict'
  ```

  It is recommended to enable this in CI to find deprecation issues, but not
  in production because enabling it comes with a performance penalty.

- **Performance improvements 🎉**: Several internal changes have made the
  library run singificantly faster. The changes:

  - Improve performance of duration calculations. (#168)
  - Early exit when no changes are needed to bring tags and metric names to
    normalized form. (#173)
  - Refactor method argument handling to reduce object allocations and
    processing. (#174)

  A benchmark suite was added (#169) and it now runs as part of CI (#170) so we
  can more easily spot performance regressions before they get merged into the
  library.

  The result of this work:

  ```
  Comparison:
  StatsD metrics to local UDP receiver (branch: master, sha: 2f98046):    10344.9 i/s
  StatsD metrics to local UDP receiver (branch: v2.4.0, sha: 371d22a):     8556.5 i/s - 1.21x  (± 0.00) slower
  ```

  The deprecations mentioned above will allows us to provide an even greater
  performance improvement, so update your code base to not use those
  deprecations anymore, and keep your eyes open for future releases of the
  library!

- _Bugfix:_ avoid deadlock when an error occurs in the integration test suite (#175)

## Version 2.4.0

- Add `StatsD.default_tags` to specify tags that should be included in all metrics. (#159)
- Improve assertion message when asserting metrics whose tags do not match. (#100)
- Enforce the Shopify Ruby style guide. (#164)
- Migrate CI to Github actions. (#158)
- Make the library frozen string literal-compatible. (#161, #163)
- Fix all Ruby warnings. (#162)

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
