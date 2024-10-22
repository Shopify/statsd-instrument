# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using the return value of StatsD metric calls, which is deprecated.
      # To check your codebase, use the following Rubocop invocation:
      #
      #     rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #       --only StatsD/MetricReturnValue
      #
      # This cop cannot autocorrect offenses. In production code, StatsD should be used in a fire-and-forget
      # fashion. This means that you shouldn't rely on the return value. If you really need to access the
      # emitted metrics, you can look into `capture_statsd_calls`
      class MetricReturnValue < Base
        include RuboCop::Cop::StatsD

        MSG = "Do not use the return value of StatsD metric methods"

        INVALID_PARENTS = [:lvasgn, :array, :pair, :send, :return, :yield]

        def on_send(node)
          if metric_method?(node) && node.arguments.last&.type != :block_pass
            add_offense(node.parent) if INVALID_PARENTS.include?(node.parent&.type)
          end
        end
      end
    end
  end
end
