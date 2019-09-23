# frozen-string-literal: true

module RuboCop
  module Cop
    module StatsD
      class PositionalArguments < Cop
        MSG = 'Use keyword arguments for StatsD calls'

        STATSD_SINGLETON_METHODS = %i{increment gauge measure set histogram distribution key_value}
        NON_POSITIONAL_SECOND_ARGUMENT_TYPES = [:block_pass, :hash]

        def on_send(node)
          if node.receiver&.type == :const && node.receiver&.const_name == "StatsD"
            if STATSD_SINGLETON_METHODS.include?(node.method_name)
              arguments = node.arguments
              if arguments.length > 2 && !NON_POSITIONAL_SECOND_ARGUMENT_TYPES.include?(arguments[2].type)
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

            value_argument = node.arguments[1]
            from = value_argument.source_range.end_pos
            to = positial_arguments.last.source_range.end_pos
            range = Parser::Source::Range.new(node.source_range.source_buffer, from, to)
            corrector.remove(range)

            keyword_arguments = []
            sample_rate = positial_arguments[0]
            if sample_rate && sample_rate.type != :nil
              keyword_arguments << "sample_rate: #{sample_rate.source_range.source}"
            end

            tags = positial_arguments[1]
            if tags && tags.type != :nil
              keyword_arguments << if tags.type == :hash && tags.source_range.source[0] != '{'
                "tags: { #{tags.source_range.source} }"
              else
                "tags: #{tags.source_range.source}"
              end
            end

            unless keyword_arguments.empty?
              corrector.insert_after(value_argument.source_range, ", #{keyword_arguments.join(', ')}")
            end
          end
        end
      end
    end
  end
end
