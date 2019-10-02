# frozen-string-literal: true

require_relative '../rubocop' unless defined?(RuboCop::Cop::StatsD)

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
      class MetricValueKeywordArgument < Cop
        include RuboCop::Cop::StatsD

        MSG = 'Do not use the value keyword argument, but use a positional argument'

        def on_send(node)
          if metric_method?(node)
            last_argument = if node.arguments.last&.type == :block_pass
              node.arguments[node.arguments.length - 2]
            else
              node.arguments[node.arguments.length - 1]
            end

            check_keyword_arguments_for_value_entry(node, last_argument) if last_argument&.type == :hash
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
