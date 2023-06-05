# frozen_string_literal: true

require_relative "../rubocop" unless defined?(RuboCop::Cop::StatsD)

module RuboCop
  module Cop
    module StatsD
      # This Rubocop will check for using the StatsD metric methods (e.g. `StatsD.instrument`)
      # for positional argument usage, which is deprecated.
      #
      # Use the following Rubocop invocation to check your project's codebase:
      #
      #     rubocop --require `bundle show statsd-instrument`/lib/statsd/instrument/rubocop.rb \
      #       --only StatsD/PositionalArguments
      #
      # This cop can autocorrect some offenses it finds, but not all of them.
      class PositionalArguments < Base
        extend AutoCorrector
        include RuboCop::Cop::StatsD

        MSG = "Use keyword arguments for StatsD calls"

        POSITIONAL_ARGUMENT_TYPES = Set[:int, :float, :nil]
        UNKNOWN_ARGUMENT_TYPES = Set[:send, :const, :lvar, :splat]
        REFUSED_ARGUMENT_TYPES = POSITIONAL_ARGUMENT_TYPES | UNKNOWN_ARGUMENT_TYPES

        KEYWORD_ARGUMENT_TYPES = Set[:hash]
        BLOCK_ARGUMENT_TYPES = Set[:block_pass]
        ACCEPTED_ARGUMENT_TYPES = KEYWORD_ARGUMENT_TYPES | BLOCK_ARGUMENT_TYPES

        def on_send(node)
          if metric_method?(node) && node.arguments.length >= 3
            case node.arguments[2].type
            when *REFUSED_ARGUMENT_TYPES
              add_offense(node) do |corrector|
                autocorrect(corrector, node)
              end
            when *ACCEPTED_ARGUMENT_TYPES
              nil
            else
              $stderr.puts "[StatsD/PositionalArguments] Unhandled argument type: #{node.arguments[2].type.inspect}"
            end
          end
        end

        def autocorrect(corrector, node)
          positional_arguments = if node.arguments.last.type == :block_pass
            node.arguments[2...node.arguments.length - 1]
          else
            node.arguments[2...node.arguments.length]
          end

          case positional_arguments[0].type
          when *UNKNOWN_ARGUMENT_TYPES
            # We don't know whether the method returns a hash, in which case it would be interpreted
            # as keyword arguments. In this case, the fix would be to add a keyword splat:
            #
            # `StatsD.instrument('foo', 1, method_call)`
            # => `StatsD.instrument('foo', 1, **method_call)`
            #
            # However, it's also possible this method returns a sample rate, in which case the fix
            # above will not do the right thing.
            #
            # `StatsD.instrument('foo', 1, SAMPLE_RATE_CONSTANT)`
            # => `StatsD.instrument('foo', 1, sample_rate: SAMPLE_RATE_CONSTANT)`
            #
            # Because of this, we will not auto-correct and let the user fix the issue manually.
            nil

          when *POSITIONAL_ARGUMENT_TYPES
            value_argument = node.arguments[1]
            from = value_argument.source_range.end_pos
            to = positional_arguments.last.source_range.end_pos
            range = Parser::Source::Range.new(node.source_range.source_buffer, from, to)
            corrector.remove(range)

            keyword_arguments = []
            sample_rate = positional_arguments[0]
            if sample_rate && sample_rate.type != :nil
              keyword_arguments << "sample_rate: #{sample_rate.source}"
            end

            tags = positional_arguments[1]
            if tags && tags.type != :nil
              keyword_arguments << if tags.type == :hash && tags.source[0] != "{"
                "tags: { #{tags.source} }"
              else
                "tags: #{tags.source}"
              end
            end

            unless keyword_arguments.empty?
              corrector.insert_after(value_argument.source_range, ", #{keyword_arguments.join(", ")}")
            end

          end
        end
      end
    end
  end
end
