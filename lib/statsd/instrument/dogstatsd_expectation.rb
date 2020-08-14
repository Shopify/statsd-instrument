# frozen_string_literal: true

module StatsD
  module Instrument
    # @private
    class DogStatsDExpectation < StatsD::Instrument::Expectation
      class << self
        # TODO: Consider adding event here too
        # def event(name, value = nil, **options)
        #   new(type: :_sc, name: name, value: value, **options)
        # end

        def service_check(name, value = nil, **options)
          new(type: :_sc, name: name, value: value, **options)
        end
      end

      attr_accessor :message

      def initialize(type:, message: nil, **options)
        if type == :_sc
          @message = message
          options[:value] = normalized_value_for_type(type, options[:value]) if options[:value]
        else
          raise ArgumentError, '`message:` only allowed with `type: :_sc`' if message
        end

        super(type: type, **options)
      end

      def normalized_value_for_type(type, value)
        case type
        when :_sc
          # FIXME: Consolidate this
          if value.is_a?(Integer)
            value
          else
            { ok: 0, warning: 1, critical: 2, unknown: 3 }.fetch(value.to_sym)
          end
        else
          super
        end
      end

      def matches(actual_metric)
        return false if message && message != actual_metric.message

        super
      end

      # FIXME: Inaccurate for service check
      def to_s
        str = +"#{name}:#{value || '<anything>'}|#{type}"
        str << "|@#{sample_rate}" if sample_rate
        str << "|#" << tags.join(',') if tags
        str << " (expected #{times} times)" if times > 1
        str
      end

      def inspect
        "#<StatsD::Instrument::DogStatsDExpectation:\"#{self}\">"
      end

      private

    end
  end
end
