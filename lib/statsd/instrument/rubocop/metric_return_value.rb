# frozen-string-literal: true

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using the return value of StatsD metric calls, which is deprecated.
      # To run, use the following command:
      #
      #     rubocop --require /absolute/path/to/metric_return_value.rb --only StatsD/MetricReturnValue filename
      #
      # This cop cannot autocorrect offenses. In production code, StatsD should be used in a fire-and-forget
      # fashion. This means that you shouldn't rely on the return value. If you really need to access the
      # emitted metrics, you can look into `capture_statsd_calls`
      class MetricReturnValue < Cop
        MSG = 'Do not use the return value of StatsD metric methods'

        STATSD_METRIC_METHODS = %i{increment gauge measure set histogram distribution key_value}
        INVALID_PARENTS = %i{lvasgn array pair send return yield}

        def on_send(node)
          if node.receiver&.type == :const && node.receiver&.const_name == "StatsD"
            if STATSD_METRIC_METHODS.include?(node.method_name) && node.arguments.last&.type != :block_pass
              add_offense(node.parent) if INVALID_PARENTS.include?(node.parent&.type)
            end
          end
        end
      end
    end
  end
end
