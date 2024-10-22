# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for providing the value for a metric using a keyword argument, which is
      # deprecated. Use the following Rubocop invocation to check your project's codebase:
      #
      #    rubocop --require \
      #      `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #      --only StatsD/MetricValueKeywordArgument
      #
      # This cop will not autocorrect offenses. Most of the time, these are easy to fix by providing the
      # value as the second argument, rather than a keyword argument.
      #
      # `StatsD.increment('foo', value: 3)` => `StatsD.increment('foo', 3)`
      class MetricValueKeywordArgument < Base
        include RuboCop::Cop::StatsD

        MSG = <<~MSG
          Do not use the StatsD.metric('name', value: <value>, ...). The `value` keyword argument is deprecated.

          Use a positional argument instead: StatsD.metric('name', <value>, ...).
        MSG

        def on_send(node)
          if metric_method?(node) && has_keyword_argument?(node, :value)
            add_offense(node)
          end
        end
      end
    end
  end
end
