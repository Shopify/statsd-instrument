# frozen-string-literal: true

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for providing the value for a metric using a keyword argument, which is
      # deprecated. Use the following Rubocop invocation to check your project's codebase:
      #
      #    rubocop --require \
      #      `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/metric_value_keyword_argument.rb \
      #      --only StatsD/MetricValueKeywordArgument
      #
      # This cop will not autocorrect offenses. Most of the time, these are easy to fix by providing the
      # value as the second argument, rather than a keyword argument.
      #
      # `StatsD.increment('foo', value: 3)` => `StatsD.increment('foo', 3)`
      #
      class MetricValueKeywordArgument < Cop
        MSG = 'Do not use the value keyword argument, but use a positional argument'

        STATSD_METRIC_METHODS = %i{increment gauge measure set histogram distribution key_value}

        def on_send(node)
          if node.receiver&.type == :const && node.receiver&.const_name == "StatsD"
            if STATSD_METRIC_METHODS.include?(node.method_name)
              last_argument = if node.arguments.last&.type == :block_pass
                node.arguments[node.arguments.length - 2]
              else
                node.arguments[node.arguments.length - 1]
              end

              check_keyword_arguments_for_value_entry(node, last_argument) if last_argument&.type == :hash
            end
          end
        end

        def check_keyword_arguments_for_value_entry(node, keyword_arguments)
          value_pair_found = keyword_arguments.child_nodes.any? do |pair|
            pair.child_nodes[0].type == :sym && pair.child_nodes[0].value == :value
          end
          add_offense(node) if value_pair_found
        end
      end
    end
  end
end
