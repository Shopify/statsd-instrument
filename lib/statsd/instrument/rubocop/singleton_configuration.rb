# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for calls to StatsD singleton configuration methods
      # (e.g. `StatsD.prefix`). The library is moving away from having just a single
      # singleton client, so these methods are deprecated.
      #
      # Use the following Rubocop invocation to check your project's codebase:
      #
      #     rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #       --only StatsD/SingletonConfiguration
      #
      # This cop will not autocorrect violations. There are several ways of fixing the violation.
      #
      # - The best option is to configure the library using environment variables, like
      #   `STATSD_ADDR`, `STATSD_IMPLEMENTATION`, `STATSD_PREFIX`, and `STATSD_DEFAULT_TAGS`.
      #   Metric methods called on the StatsD singleton (e.g. `StatsD.increment`) will by default
      #   be delegated to a client that is configured using these environment variables.
      # - Alternatively, you can instantiate your own client using `StatsD::Instrument::Client.new`,
      #   and assign it to `StatsD.singleton_client`. The client constructor accepts many of the
      #   same options.
      # - If you have to, you can call the old methods on `StatsD.legacy_singleton_client`. Note
      #   that this option will go away in the next major version.
      class SingletonConfiguration < Base
        include RuboCop::Cop::StatsD

        MSG = <<~MESSAGE
          Singleton methods to configure StatsD are deprecated.

          - The best option is to configure the library using environment variables, like
            `STATSD_ADDR`, `STATSD_IMPLEMENTATION`, `STATSD_PREFIX`, and `STATSD_DEFAULT_TAGS`.
            Metric methods called on the StatsD singleton (e.g. `StatsD.increment`) will by default
            be delegated to a client that is configured using these environment variables.
          - Alternatively, you can instantiate your own client using `StatsD::Instrument::Client.new`,
            and assign it to `StatsD.singleton_client`. The client constructor accepts many of the
            same options.
          - If you have to, you can call the old methods on `StatsD.legacy_singleton_client`. Note
            that this option will go away in the next major version.
        MESSAGE

        def on_send(node)
          if singleton_configuration_method?(node)
            add_offense(node)
          end
        end
      end
    end
  end
end
