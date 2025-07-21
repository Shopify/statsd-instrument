# Changelog

This file documents the changes between releases of this library. When
creating a pull request, please add an entry to the "unreleased changes"
section below.

## Unreleased changes

## Version 3.9.10

- [#398](https://github.com/Shopify/statsd-instrument/pull/398) - Fix metrics not being sent from signal trap contexts when aggregation is enabled.
  When the aggregator is enabled and metrics are emitted from within a signal handler (e.g., SIGTERM, SIGINT), 
  the thread health check would fail with `ThreadError: can't be called from trap context` due to mutex 
  synchronization. The aggregator now gracefully falls back to direct writes when called from a trap context, 
  ensuring metrics are not lost during signal handling such as graceful shutdowns.

## Version 3.9.9

- [#392](https://github.com/Shopify/statsd-instrument/pull/392) - Prevent ENOBUFS errors when using UDP, by skipping setting socket buffer size.

## Version 3.9.8

- [#390](https://github.com/Shopify/statsd-instrument/pull/391) - Fixing bug in Environment when using UDS. The max packet size option was not being passed to the 
UDS connection, causing messages that were too large to be dropped (specially sensitive when used together with BatchedSink).

## Version 3.9.7

- [#389](https://github.com/Shopify/statsd-instrument/pull/389) - Fixing bug with BatchedSink constructor when using UDS, the constructor was not properly passing the Sink to the BatchedSink.

## Version 3.9.6

- [#388](https://github.com/Shopify/statsd-instrument/pull/388) - Properly fixing the bug when using aggregation and sending sampled
histograms, now the client will respect the sampling rate when sending the metrics and pass it down to the aggregator.

## Version 3.9.5

- [#387](https://github.com/Shopify/statsd-instrument/pull/387) - Fixing bug when using aggregation and sending sampled
histogram metrics, they will not be scaled properly because of missing sampling rate in the final sent sample.

## Version 3.9.4

- [#384](https://github.com/Shopify/statsd-instrument/pull/384) - Aggregation: fixing bug when sending metrics synchronously
e.g. when the main thread is killed and we are forced to flush the metrics.

## Version 3.9.3

- [#382](https://github.com/Shopify/statsd-instrument/pull/382) - Fix warnings in Rubocop cops.

## Version 3.9.2

- [#381](https://github.com/Shopify/statsd-instrument/pull/381) - Reduce log level of some messages inside new Aggregator
to avoid contention and verbosity.

## Version 3.9.1

- [#378](https://github.com/Shopify/statsd-instrument/pull/378) - Respect sampling rate when aggregation is enabled, just for timing metrics.
  Not respecting sampling rate, incurs in a performance penalty, as we will send more metrics than expected.
  Moreover, it overloads the StatsD server, which has to send out and process more metrics than expected.

## Version 3.9.0

- Introduced an experimental aggregation feature to improve the efficiency of metrics reporting by aggregating 
multiple metric events into a single sample. This reduces the number of network requests and can significantly 
decrease the overhead associated with high-frequency metric reporting. To enable metric aggregation, set the 
`STATSD_ENABLE_AGGREGATION` environment variable to true. More information on this feature is available in the README.
- Added support for sending StatsD via Unix domain sockets. This feature is enabled by
setting the `STATSD_SOCKET` environment variable to the path of the Unix domain socket.
  - :warning: **Possible breaking change**: We removed/renamed some classes and now Sinks are generic, so the classes `UDPSink` and `UDPBatchedSink` are now called
`StatsD::Instrument::Sink` and `StatsD::Instrument::BatchedSink` respectively.
If you used those internal classes, you will need to update your code to use the new classes.

## Version 3.8.0

- UDP batching will now track statistics about its own batching performance, and
  emit those statistics to the default sink when `STATSD_BATCH_STATISTICS_INTERVAL`
  is set to any non-zero value. The default value is zero; additional information
  on statistics tracked is available in the README.

## Version 3.7.0

- Add public `.flush` method to sink classes.

## Version 3.6.1

- Fix `ArgumentError` when passing an empty Hash as tags.

## Version 3.6.0

- Optimized datagram building.

## Version 3.5.12

- Update CONTRIBUTING docs about release process
- Rename branch `master` to `main`.

## Version 3.5.11

- Fix a bug where passing `nil` to `clone_with_options` did not overwrite existing values

## Version 3.5.10

- Fix rubocop 1.30 compatibilitty

## Version 3.5.9

- Fix dynamic tags being evaluated only once.

## Version 3.5.8

- Allow the `tag_error_class` option for `statsd_count_success` in strict mode.

## Version 3.5.7

- Improve time measurement to avoid seconds to milliseconds conversions.

## Version 3.5.6

- Fix issue from 3.5.5 where tests using RSpec matcher for tag assertion would fail, because the matcher as being
  use as an array.

## Version 3.5.5

- Fix issue on 3.5.4, allowing user to specify compound matcher without tags

## Version 3.5.4

- Allow user to assert different tags using RSpec composable matcher

## Version 3.5.3

- Improve shapes friendliness for Ruby 3.2+

## Version 3.5.2

- Fix bug on assertions to allow the user passes `times: 0` as expectation.

## Version 3.5.1

- Fix bug when passing a lambda function to dynamically set the tags in the strict mode.

## Version 3.5.0

- Allow user to provide a lambda function to dynamically set metric tags

## Version 3.4.0

- UDP Batching has been largely refactored again. The `STATSD_FLUSH_INTERVAL` environment variable
  is deprecated. It still disable batching if set to `0`, but other than that is has no effect.
  Setting `STATSD_BUFFER_CAPACITY` to `0` is now the recommended way to disable batching.
- The synchronous UDP sink now use one socket per thread, instead of a single socket
  protected by a mutex.

## Version 3.3.0

- UDP Batching now has a max queue size and emitter threads will block if the queue
  reaches the limit. This is to prevent the queue from growing unbounded.
  More generally the UDP batching mode was optimized to improve throughput and to
  flush the queue more eagerly (#309).
- Added `STATSD_BUFFER_CAPACITY` configuration.
- Added `STATSD_MAX_PACKET_SIZE` configuration.
- Require `set` explicitly, to avoid breaking tests for users of this library (#311)

## Version 3.2.1

- Fix a bug in UDP batching that could cause the Ruby process to be stuck on exit (#291).

## Version 3.2.0

- Add `tag_error_class` option to `statsd_count_success` which tags the class of a thrown error

## Version 3.1.2

 - Fix bug when passing custom client to expectation.

## Version 3.1.1

 - Improved flushing of buffered datagrams on process exit when using UDP batching.

## Version 3.1.0

- Introduced UDP batching using a dispatcher thread, and made it the
  production default.
- Dropped support for Ruby 2.4 and 2.5.

## Version 3.0.2

- Properly handle no_prefix when using StatsD assertions.

## Version 3.0.1

- Fix metaprograming methods to not print keyword argument warnings on
  Ruby 2.7.
- Fix the gemspec to no longer register `rake` and `rubocop` as executables.

## Version 3.0.0

This version makes the new client that was added in version 2.6+ the default
client, and removes the legacy client.

- All previously deprecated functionality has been removed (since version 2.5,
  see below).
- Support for the StatSite implementation has been dropped.
- Support for Ruby version older than 2.4 has been dropped.
- The default implementation has been changed to DataDog. To use the standard
  StatsD implementation (which was the default in v2), set the
  `STATSD_IMPLEMENTATION` environment variable to `statsd`.

To upgrade, follow the following process:

1. Upgrade to version 2.9.2.
2. Switch to the new client by setting the `STATSD_USE_NEW_CLIENT` environment
   variable to 1.
   - You may want to use the Rubocop rules that ship with this library, and
     strict mode to find and fix deprecated usage patterns. See below for more
     information about strict mode and the available Rubocop rules.
3. Upgrade to version 3.0.0, and unset `STATSD_USE_NEW_CLIENT`.

## Version 2.9.2

- Allow providing a value as second positional argument to `assert_statsd_*`
  methods, rather than as keyword argument. This matches the arguments to the
  StatsD metric call.
  ``` ruby
    assert_statsd_increment('batch_size', 10) do
      StatsD.increment('batch_size', 10)
    end
  ```

## Version 2.9.1

- The `VOID` object being returned by metric methods (e.g. `StatsD.increment`)
  is now a subclass of `Object` rather than `BasicObject`, which means that
  common methods will work as expected (`#class`, `#tap`).

## Version 2.9.0

- ⚠️ **DEPRECATION:**  The `StatsD.key_value` metric method is deprecated
  and will be removed in version 3.0. The new client does not have StatSite
  support. Due to the lack of active contributors that can port this metric
  type to the new client, we have decided to drop it until somebody else
  steps up and re-adds it to the new client.
- Fix: metaprogramming methods will send metrics to the client assifgned to
  `StatsD.singleton_client` when the metric is emitted, rather than the client
  when the metaprogramming method was called.
- Metric methods (e.g. `StatsD.increment`) on the new client will now return a
  `VOID` object that evaluates to `true` rather than nil. This is for better
  backwards compatibility with the legacy client.
- Add support for variadic arguments to `assert_no_statsd_calls`. This allows
  consolidation of assertions about specific metrics. For example:
    ```diff
    -assert_no_statsd_calls('foo') do
    -  assert_no_statsd_calls('bar') do
    -    assert_no_statsd_calls('biz.baz') do
    +assert_no_statsd_calls('foo', 'bar', 'biz.baz') do
           # do work...
    -    end
    -  end
     end
    ```

## Version 2.8.0

- ⚠️ Remove support for `assert_statsd_*(..., ignore_tags: ...)`. This feature
  was never documented, and the only use case we were aware of has been
  addressed since. It's highly unlikely that you are using this feature.
  However, if you are, you can capture StatsD datagrams using the
  `capture_statsd_datagrams` method, and run your own assertions on the list.
- ⚠️ Remove `StatsD.client`. This was added in version 2.6.0 in order to
  experiment with the new client. However, at this point there are better ways
  to do this.
  - You can set `StatsD.singleton_client` to a new client, which causes the
    calls to the StatsD singleton to be handled by a new client. If you set
    `STATSD_USE_NEW_CLIENT`, it will be initialized to a new client.
  - If that doesn't work for you, you can instantiate a client using
    `StatsD::Instrument::Client.from_env` and assign it to a variable of your
    own choosing.
- Fix some compatibility issues when using `assert_statsd_*` methods when
  using a new client with prefix.

## Version 2.7.1

This release has some small fixes related to the new client only:

- Bugfix: Fix the metaprogramming methods so they work with a new client when
  strict mode is _not_ enabled.
- Make it easier to instantiate new clients by specifying an implementation
  (e.g. `datadog`) rather than a DatagramBuilder class.
- Change `NullSink#sample?` to always return `true`, so it's easier to verify
  business rules by using a different DatagramBuilder in test suites.

## Version 2.7.0

This release allows you to switch the StatsD singleton to use the new, more
performant client. By setting `STATSD_USE_NEW_CLIENT` as environment variable
methods called on the StatsD singleton (e.g. `StatsD.increment`) will be
delegated to an instance of the new client, configured using environment
variables.

The new client should be mostly compatible with the legacy client, but some
deprecated functionality will no longer work. See the changelog for version
2.6.0 and 2.5.0 for more information about the deprecations, and how to find
and fix deprecations in your code base.

- The old legacy client that was implemented on the `StatsD` singleton has
  been moved to `StatsD::LegacyClient.singleton`. By default, all method
  calls on the `StatsD` singleton will be delegated to this legacy client.
- By setting `STATSD_USE_NEW_CLIENT` as environment variable, these method
  calls will be delegated to an instance of the new client instead. This
  client is configured using the existing `STATSD_*` environment variables,
  like `STATSD_ADDR` and `STATSD_IMPLEMENTATION`.
- You can also assign a custom client to `StatsD.singleton_client`.

The `assert_statsd_*` methods have been reworked to support asserting StatsD
datagrams coming from a legacy client, or from a new client.

- By default, the assertion methods will capture metrics emitted from
  `StatsD.singleton_client`.
- You can provide a `client` argument if you want to assert metrics being
  emitted by a different client. E.g.

  ``` ruby
    assert_statsd_increment('foo', client: my_custom_client) do
      my_custom_client.increment('foo')
    end
  ```

- You can also capture metrics yourself, and then run assertions on them
  by providing a `datagrams` argument:

  ``` ruby
    datagrams = my_custom_client.capture do
      my_custom_client.increment('foo')
    end
    assert_statsd_increment('foo', datagrams: datagrams)
  ```

  This makes it easy to run multiple assertions on the set of metrics that
  was emitted without having to nest calls.

- **⚠️ DEPRECATION** The `assert_statsd_*`-family of methods now use keyword
  arguments, rather than option hashes. This means that calls that use
  unsupported arguments will raise an `ArgumentError` now, rather than silently
  ignoring unknown keys.

- **⚠️ DEPRECATION**: The following methods to configure the legacy client
  are deprecated:

  - `Statsd.backend`
  - `StatsD.default_sample_rate`
  - `StatsD.default_tags`
  - `StatsD.prefix`

  We recommend configuring StatsD using environment variables, which will be
  picked up by the new client as well. You can also instantiate a new client
  yourself; you can provide similar configuration options to
  `StatsD::Instrument::Client.new`.

  You can use the following Rubocop invocation to find any occurrences of
  these deprecated method calls:

  ``` sh
    rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      --only StatsD/SingletonConfiguration
  ```

## Version 2.6.0

This release contains a new `StatsD::Instrument::Client` class, which is
slated to replace the current implementation in the next major release.

The main reasons for this rewrite are two folds:
- Improved performance.
- Being able to instantiate multiple clients.

We have worked hard to make the new client as compatible as possible. However,
to accomplish some of our goals we have deprecated some stuff that we think
is unlikely to be used. See the rest of the release notes of this version, and
version 2.5.0 to see what is deprecated.

You can test compatibility with the new client by replacing `StatsD` with
`StatsD.client`, which points to a client that will be instantiated using
the same environment variables that you can already use for this library. You
can also use strict mode, and rubocop rules to check whether you are using any
deprecated patterns. See below for more info.

- **⚠️ DEPRECATION**: Using the `prefix: "foo"` argument for `StatsD.metric`
  calls (and the metaprogramming macros) is deprecated.

  - You can include the prefix in the metric name.
  - If you want to override the global prefix, set `no_prefix: true` and
    include the desired prefix in the metric name

  This library ships with a Rubocop rule to detect uses of this keyword
  argument in your codebase:

  ``` sh
  # Check for the prefix arguments on your StatsD.metric calls
  rubocop --only StatsD/MetricPrefixArgument \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb
  ```

  Strict mode has also been updated to no longer allow this argument.

- **⚠️ DEPRECATION**: Using the `as_dist: true` argument for `StatsD.measure`
  and `statsd_measure` methods is deprecated. This argument was only available
  for internal use, but was exposed in the public API. It is unlikely that you
  are using this argument, but you can check to make sure using this Rubocop
  invocation:

  ``` sh
  # Check for the as_dist arguments on your StatsD.measure calls
  rubocop --only StatsD/MeasureAsDistArgument \
    -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb
  ```

  Strict mode has also been updated to no longer allow this argument.

- You can now enable strict mode by setting the `STATSD_STRICT_MODE`
  environment variable. No more need to change your Gemfile! Note that it is
  still not recommended to enable strict mode in production due to the
  performance penalty, but is recommended for development and test. E.g. use
  `STATSD_STRICT_MODE=1 rails test` to run your test suite with strict mode
  enabled to expose any deprecations in your codebase.

- Add support for `STATSD_PREFIX` and `STATSD_DEFAULT_TAGS` environment variables
  to configure the prefix to use for metrics and the comma-separated list of tags
  to apply to every metric, respectively.

  These environment variables are preferred over using `StatsD.prefix` and
  `StatsD.default_tags`: it's best practice to configure the StatsD library
  using environment variables.

- Several improvements to `StatsD.event` and `StatsD.service_check` (both are
  Datadog-only). The previous implementation would sometimes construct invalid
  datagrams based on the input. The method signatures have been made more
  explicit, and documentation of these methods is now also more clear.

- Slight behaviour change when using the `assert_statsd_*` assertion methods in
  combination with `assert_raises`: we now do not allow the block passed to the
  `assert_statsd_` call to raise an exception. This may cause tests to fail that
  previously were succeeding.

  Consider the following example:

  ``` ruby
  assert_raises(RuntimeError) do
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

  Now, we fail the test because an unexpected exception occurred inside the block.
  This means that the following test will fail:
s
  ``` ruby
  assert_raises(RuntimeError) do
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
    assert_raises(RuntimeError) do
      StatsD.increment('foo')
      raise 'something unexpected'
    end
  end
  ```

  See #193, #184, and #166 for more information.

## Version 2.5.1

- **Bugfix:** when using metaprogramming methods, changes to `StatsD.prefix` after
  the metaprogramming method was evaluated would not be respected. This
  unfortunately is quite common when you set the StatsD prefix inside an
  initializer. This issue is now addressed: the prefix is evaluated at the
  moment the metric is emitted, not when the metaprogramming method is being
  evaluated. (#202)

## Version 2.5.0

- **⚠️ DEPRECATION**: Providing a sample rate and tags to your metrics and method
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

- **⚠️ DEPRECATION**: Relying on the return value of the StatsD metric methods
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
  gem 'statsd-instrument', require: 'statsd/instrument/strict'

  # Or, in your test helper:
  require 'statsd/instrument/strict'
  ```

  It is recommended to enable this in CI to find deprecation issues, but not
  in production because enabling it comes with a performance penalty.

- **Performance improvements 🎉**: Several internal changes have made the
  library run significantly faster. The changes:

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

- Re-add `StatsD::Instrument.duration`, which was accidentally removed since version 2.5.3 (#157)

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

## Version 2.3.0

- No changes from `beta6`, distributions are GA at DataDog so making the distribution changes GA in gem

## Version 2.3.0.beta6

- Fix invalidate socket on connectivity issues in UDP (#135)

## Version 2.3.0.beta5

- Fixes bug in return value for blocks used in distributions (#132)

## Version 2.3.0.beta4

- Add support for distribution to accept a block
- Add class method for defining and removing a distribution from a method (same as a measure)
- Refactor most instrument methods to reduce code duplication

## Version 2.3.0.beta3

- fix for `:as_dist` parameter in the `statsd_measure` class method

## Version 2.3.0.beta2

- Add support for specifying a measure to emit as a distribution using `:as_dist` parameter

## Version 2.3.0.beta

- Add support for beta, Datadog specific distribution metrics
- Invalidate socket on connectivity issues

## Version 2.2.1

- Fix performance regression from v2.2.0

## Version 2.2.0

- Add support for two new Datadog specific metric types: events and service checks.

## Version 2.1.3

- The `assert_statsd_calls` test helper will now raise an exception whenever a block isn't passed.
- Sending stats inside an exit handler will no longer cause programs to exit abruptly.

## Version 2.1.2

- Use `prepend` instead of rewriting classes for metaprogramming methods.
- RSpec: make matchers more flexible.
- Bugfix: Only ask Rails for the environment when it's actually loaded.

## Version 2.1.1

- Add `assert_statsd_calls` to from validating cases where one has multiple metrics with the same name and type being recorded, but with different options.

## Version 2.1.0

- Fix rspec-rails compatibility
- Add `value` keyword argument to all metric types.

## Version 2.0.12

- Make StatsD client thread-safe
- Assertions: Ensure sample rates have proper values.
- Assertions: Make tag assertions work more intuitively
- RSpec: Add backwards compatibility for RSpec 2

## Version 2.0.11

- Don't change method visibility when adding instrumentation to methods using metaprogramming
- RSpec: add support for Compound expectations

## Version 2.0.10

- Assertions: allow ignoring certain tags when asserting for other tags to be present.

## Version 2.0.9

- Better error message for `assert_no_statsd_calls`

## Version 2.0.8

- More tag handling performance improvements.
- RSpec matchers documentation improvements

## Version 2.0.7

- Tag handling performance improvements.
- Test against Ruby 2.2.
- Drop support for Ruby 1.9.3.

## Version 2.0.6

- Fix some loading order issues in Rails environments.
- Default behavior: in a **staging** environment, the defaults are now the same as in a **production environment**.
- Documentation overhaul

## Version 2.0.5

- Allow for nested assertions using the `assert_statsd_*` assertion methods.

## Version 2.0.4

- Add a Railtie to fix some initialization issues.

## Version 2.0.3

- Assertion method bugfixes

## Version 2.0.2

- Documentation fixes

## Version 2.0.1

- Add assertion methods `assert_statsd_histogram`, `assert_statsd_set`, and `assert_statsd_key_value`.

## Version 2.0.0

- Complete rewrite using pluggable backends.
- Add assertion methods in `StatsD::Instrument::Assertions` to make testing easier and less brittle.
- Drop support for Ruby 1.8
