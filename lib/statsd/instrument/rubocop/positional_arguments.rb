# frozen-string-literal: true

module RuboCop
  module Cop
    module StatsD
      class PositionalArguments < Cop
        MSG = 'Use keyword arguments for StatsD calls'

        STATSD_SINGLETON_METHODS = %i{increment gauge measure set histogram distribution key_value}
        POSITIONAL_ARGUMENT_TYPES = Set[:int, :float, :nil]
        UNKNOWN_ARGUMENT_TYPES = Set[:send, :const]
        REFUSED_ARGUMENT_TYPES = POSITIONAL_ARGUMENT_TYPES | UNKNOWN_ARGUMENT_TYPES

        def on_send(node)
          if node.receiver&.type == :const && node.receiver&.const_name == "StatsD"
            if STATSD_SINGLETON_METHODS.include?(node.method_name)
              arguments = node.arguments
              if arguments.length >= 3 && REFUSED_ARGUMENT_TYPES.include?(arguments[2].type)
                add_offense(node)
              end
            end
          end
        end

        def autocorrect(node)
          -> (corrector) do
            positial_arguments = if node.arguments.last.type == :block_pass
              node.arguments[2...node.arguments.length - 1]
            else
              node.arguments[2...node.arguments.length]
            end

            case positial_arguments[0].type
            when *UNKNOWN_ARGUMENT_TYPES
              # We don't know whether the method returns a hash, in which case it would be interpreted
              # as keyword arguments. In this case, the fix would be to add a keywordf splat:
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
              return

            when *POSITIONAL_ARGUMENT_TYPES
              value_argument = node.arguments[1]
              from = value_argument.source_range.end_pos
              to = positial_arguments.last.source_range.end_pos
              range = Parser::Source::Range.new(node.source_range.source_buffer, from, to)
              corrector.remove(range)

              keyword_arguments = []
              sample_rate = positial_arguments[0]
              if sample_rate && sample_rate.type != :nil
                keyword_arguments << "sample_rate: #{sample_rate.source}"
              end

              tags = positial_arguments[1]
              if tags && tags.type != :nil
                keyword_arguments << if tags.type == :hash && tags.source[0] != '{'
                  "tags: { #{tags.source} }"
                else
                  "tags: #{tags.source}"
                end
              end

              unless keyword_arguments.empty?
                corrector.insert_after(value_argument.source_range, ", #{keyword_arguments.join(', ')}")
              end

            else
              puts "Unknown arg type #{positial_arguments[0].type}"
            end
          end
        end
      end
    end
  end
end
