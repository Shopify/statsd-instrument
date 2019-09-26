# frozen-string-literal: true

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using splat arguments (*args) in StatsD metric calls. To run
      # this rule on your codebase, invoke Rubocop this way:
      #
      #    rubocop --require \
      #      `bundle show statsd-instrument`/lib/statsd/instrument/rubocop/splat_arguments.rb \
      #      --only StatsD/SplatArguments
      #
      # This cop will not autocorrect offenses.
      class SplatArguments < Cop
        MSG = 'Do not use splat arguments in StatsD metric calls'

        STATSD_METRIC_METHODS = %i{increment gauge measure set histogram distribution key_value}

        def on_send(node)
          if node.receiver&.type == :const && node.receiver&.const_name == "StatsD"
            if STATSD_METRIC_METHODS.include?(node.method_name)
              check_for_splat_arguments(node)
            end
          end
        end

        private

        def check_for_splat_arguments(node)
          if node.arguments.any? { |arg| arg.type == :splat }
            add_offense(node)
          end
        end
      end
    end
  end
end
