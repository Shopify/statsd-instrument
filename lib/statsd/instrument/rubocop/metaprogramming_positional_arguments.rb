# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using the metaprogramming macros for positional
      # argument usage, which is deprecated. These macros include `statsd_count_if`,
      # `statsd_measure`, etc.
      #
      # Use the following Rubocop invocation to check your project's codebase:
      #
      #     rubocop --only StatsD/MetaprogrammingPositionalArguments
      #       -r `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb
      #
      #
      # This cop will not autocorrect the offenses it finds, but generally the fixes are easy to fix
      class MetaprogrammingPositionalArguments < Base
        include RuboCop::Cop::StatsD

        MSG = "Use keyword arguments for StatsD metaprogramming macros"

        def on_send(node)
          if metaprogramming_method?(node)
            arguments = node.arguments.dup
            arguments.shift # method
            arguments.shift # metric
            arguments.pop if arguments.last&.type == :block_pass
            case arguments.length
            when 0
            when 1
              add_offense(node) if arguments.first.type != :hash
            else
              add_offense(node)
            end
          end
        end
      end
    end
  end
end
