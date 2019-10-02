# frozen-string-literal: true

require_relative '../rubocop' unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for specifying the `as_dist: true` keyword argument on `StatsD.measure`
      # and `statsd_measure`. This argument is deprecated. Instead, you can use `StatsD.distribution`
      # (or `statsd_distribution`) directly.
      #
      # To run this cop on your codebase:
      #
      #     rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #       --only StatsD/MeasureAsDist
      #
      # This cop will not autocorrect offenses.
      class MeasureAsDist < Cop
        include RuboCop::Cop::StatsD

        MSG = 'Do not use StatsD.measure(..., as_dist: true). Use StatsD.distribution instead.'

        def on_send(node)
          if metric_method?(node) && node.method_name == :measure && (hash = keyword_arguments(node))
            as_dist = hash.child_nodes.detect do |pair|
              pair.child_nodes[0]&.type == :sym &&
                pair.child_nodes[0].value == :as_dist
            end
            add_offense(node) if as_dist
          end

          if metaprogramming_method?(node) && node.method_name == :statsd_measure && (hash = keyword_arguments(node))
            as_dist = hash.child_nodes.detect do |pair|
              pair.child_nodes[0]&.type == :sym &&
                pair.child_nodes[0].value == :as_dist
            end
            add_offense(node) if as_dist
          end
        end

        def keyword_arguments(node)
          return nil if node.arguments.empty?
          last_argument = if node.arguments.last&.type == :block_pass
            node.arguments[node.arguments.length - 2]
          else
            node.arguments[node.arguments.length - 1]
          end

          last_argument&.type == :hash ? last_argument : nil
        end
      end
    end
  end
end
