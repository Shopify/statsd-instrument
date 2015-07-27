# Changelog

This file documents the changes between releases of this library. When creating a pull request,
please at an entry to the "unreleased changes" section below.

### Unreleased changes

- Drop support for Ruby 1.9.3.
- Add support for Ruby 2.2.
- Add support for OpenTSDB tags through a new `OpenTSDBBackend`.

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
