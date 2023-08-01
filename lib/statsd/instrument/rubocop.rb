# frozen_string_literal: true

module RuboCop
  module Cop
    module StatsD
      METRIC_METHODS = [:increment, :gauge, :measure, :set, :histogram, :distribution, :key_value]

      METAPROGRAMMING_METHODS = [
        :statsd_measure,
        :statsd_distribution,
        :statsd_count_success,
        :statsd_count_if,
        :statsd_count,
      ]

      SINGLETON_CONFIGURATION_METHODS = [
        :backend,
        :"backend=",
        :prefix,
        :"prefix=",
        :default_tags,
        :"default_tags=",
        :default_sample_rate,
        :"default_sample_rate=",
      ]

      private

      def metaprogramming_method?(node)
        METAPROGRAMMING_METHODS.include?(node.method_name)
      end

      def metric_method?(node)
        node.receiver&.type == :const &&
          node.receiver&.const_name == "StatsD" &&
          METRIC_METHODS.include?(node.method_name)
      end

      def singleton_configuration_method?(node)
        node.receiver&.type == :const &&
          node.receiver&.const_name == "StatsD" &&
          SINGLETON_CONFIGURATION_METHODS.include?(node.method_name)
      end

      def has_keyword_argument?(node, sym)
        if (kwargs = keyword_arguments(node))
          kwargs.child_nodes.detect do |pair|
            pair.child_nodes[0]&.type == :sym && pair.child_nodes[0].value == sym
          end
        end
      end

      def keyword_arguments(node)
        return if node.arguments.empty?

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

require_relative "rubocop/metaprogramming_positional_arguments"
require_relative "rubocop/metric_return_value"
require_relative "rubocop/metric_value_keyword_argument"
require_relative "rubocop/positional_arguments"
require_relative "rubocop/splat_arguments"
require_relative "rubocop/measure_as_dist_argument"
require_relative "rubocop/metric_prefix_argument"
require_relative "rubocop/singleton_configuration"
