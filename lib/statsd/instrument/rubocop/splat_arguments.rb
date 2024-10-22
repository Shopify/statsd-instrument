# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using splat arguments (*args) in StatsD metric calls. To run
      # this rule on your codebase, invoke Rubocop this way:
      #
      #    rubocop --require \
      #      `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #      --only StatsD/SplatArguments
      #
      # This cop will not autocorrect offenses.
      class SplatArguments < Base
        include RuboCop::Cop::StatsD

        MSG = "Do not use splat arguments in StatsD metric calls"

        def on_send(node)
          if metric_method?(node)
            if node.arguments.any? { |arg| arg.type == :splat }
              add_offense(node)
            end
          end
        end
      end
    end
  end
end
