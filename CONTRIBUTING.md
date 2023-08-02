# Contributing

This project is MIT licensed.

> **Note**: this project is currently not actively maintained, but is heavily used in production.
> As a result, pull requests and issues may not be responded to. Also, due to the limited time we have
> available to work on this library, we cannot accept PRs that do not maintain backwards compatibility,
> or PRs that would affect the performance of the hot code paths.

## Reporting issues

Report issues using the [Github issues tracker](https://github.com/Shopify/statsd-instrument/issues/new).

When reporting issues, please include the following information:

- Your Ruby interpreter version.
- The statsd-instrument version. **Note:** only the latest version is supported.
- The StatsD backend you are using.

## Opening pull requests

1. Fork the repository, and create a branch.
2. Implement the feature or bugfix, and add tests that cover the changed functionality.
3. Create a pull request. Make sure that you get a green CI status on your commit.

Some notes:

- Make sure to follow to coding style. This is enforced by Rubocop
- Make sure your changes are properly documented using [yardoc syntax](http://www.rubydoc.info/gems/yard/file/docs/GettingStarted.md).
- Add an entry to the "unreleased changes" section of [CHANGELOG.md](./CHANGELOG.md).
- **Do not** update `StatsD::Instrument::VERSION`. This will be done during the release procedure.

### On performance & benchmarking

This gem is used in production at Shopify, and is used to instrument some of
our hottest code paths. This means that we are very careful about not
introducing performance regressions in this library.

**Important:** Whenever you make changes to the metric emission code path in
this library, you **must** include benchmark results to show the impact of
your changes.

The `benchmark/` folder contains some example benchmark script that you can
use, or can serve as a starting point. The [benchmark README](benchmark/README.md)
has instructions on how to benchmark your changes.

### On backwards compatibility

Shopify's codebases are heavily instrumented using this library. As a result, we cannot
accept changes that are backwards incompatible:

- Changes that will require us to update our codebases.
- Changes that will cause metrics emitted by this library to change in form or shape.

This means that we may not be able to accept fixes for what you consider a bug, because
we are depending on the current behavior of the library.

## Release procedure

1. Update the version number in `lib/statsd/instrument/version.rb`.
2. Move the "Unreleased changes" items in [CHANGELOG.md](./CHANGELOG.md) to a new section for the release.
3. Open a PR with these changes, have it reviewed and merged.
4. The new version will be automatically uploaded by our deployment pipeline.
