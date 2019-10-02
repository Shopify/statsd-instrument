# frozen-string-literal: true

require_relative '../rubocop' unless defined?(RuboCop::Cop::StatsD)

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
      class MetricPrefixArgument < Cop
        include RuboCop::Cop::StatsD

        MSG = <<~MSG
          Do not use StatsD.metric(..., prefix: "foo").

          This is deprecated: you can simply include the prefix in the metric name instead.
          If you want to override the global prefix, you can set `no_prefix: true`.
        MSG

        def on_send(node)
          if metric_method?(node) && (hash = keyword_arguments(node))
            prefix = hash.child_nodes.detect do |pair|
              pair.child_nodes[0]&.type == :sym &&
                pair.child_nodes[0].value == :prefix
            end
            add_offense(node) if prefix
          end

          if metaprogramming_method?(node) && (hash = keyword_arguments(node))
            prefix = hash.child_nodes.detect do |pair|
              pair.child_nodes[0]&.type == :sym &&
                pair.child_nodes[0].value == :prefix
            end
            add_offense(node) if prefix
          end
        end
      end
    end
  end
end
