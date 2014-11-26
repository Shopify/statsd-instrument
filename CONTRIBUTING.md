# Contributing

This project is MIT licensed and welcomes outside contributions.

## Reporting issues

Report issues using the [Github issues tracker](https://github.com/Shopify/statsd-instrument/issues/new).

When reporting issues, please incldue the following information:

- Your Ruby interpreter version.
- The statsd-instrument version. **Note:** only the latest version is supported.
- The StatsD backend you are using.

## Pull request

1. Fork the repository, and create a branch.
2. Implement the feature or bugfix, and add tests that cover the changed functionality.
3. Create a pull request. Make sure that you get Travis CI passes.
4. Ping **@jstorimer** and/or **@wvanbergen** for a code review.

Some notes:

- Make sure to follow to coding style.
- Make sure your changes are properly documented using [yardoc syntax](http://www.rubydoc.info/gems/yard/file/docs/GettingStarted.md).
- Add an entry to the "unreleased changes" section of [CHANGELOG.md](./CHANGELOG.md).
- **Do not** update `StatsD::Instrument::VERSION`. This will be done during the release prodecure.

## Release procedure

1. Update the version number in `lib/statsd/instrument/version.rb`.
2. Move the "Unreleased changes" items in [CHANGELOG.md](./CHANGELOG.md) to a new section for the release.
3. Commit these changes.
4. Run `bundle exec rake release`.
