# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for specifying the `prefix` keyword argument on `StatsD` metric
      # methods and `statsd_*` metaprogramming methods. To run this cop on your codebase:
      #
      #     rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #       --only StatsD/MetricPrefixArgument
      #
      # This cop will not autocorrect offenses.
      class MetricPrefixArgument < Base
        include RuboCop::Cop::StatsD

        MSG = <<~MSG
          Do not use StatsD.metric(..., prefix: "foo"). The prefix argument is deprecated.

          You can simply include the prefix in the metric name instead.
          If you want to override the global prefix, you can set `no_prefix: true`.
        MSG

        def on_send(node)
          if metric_method?(node)
            add_offense(node) if has_keyword_argument?(node, :prefix)
          end

          if metaprogramming_method?(node)
            add_offense(node) if has_keyword_argument?(node, :prefix)
          end
        end
      end
    end
  end
end
