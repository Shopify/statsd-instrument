# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

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
      #       --only StatsD/MeasureAsDistArgument
      #
      # This cop will not autocorrect offenses.
      class MeasureAsDistArgument < Base
        include RuboCop::Cop::StatsD

        MSG = <<~MSG
          Do not use StatsD.measure(..., as_dist: true). This is deprecated.

          Use StatsD.distribution (or statsd_distribution) instead.
        MSG

        def on_send(node)
          if metric_method?(node) && node.method_name == :measure
            add_offense(node) if has_keyword_argument?(node, :as_dist)
          end

          if metaprogramming_method?(node) && node.method_name == :statsd_measure
            add_offense(node) if has_keyword_argument?(node, :as_dist)
          end
        end
      end
    end
  end
end
