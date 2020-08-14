# frozen_string_literal: true

module StatsD
  module Instrument
    # @private
    class DogStatsDExpectation < StatsD::Instrument::Expectation
      class << self
        def event(name, value = nil, **options)
          DogStatsdEventExpectation.new(type: :_e, name: name, value: value, **options)
        end

        def service_check(name, value = nil, **options)
          DogStatsdServiceCheckExpectation.new(type: :_sc, name: name, value: value, **options)
        end
      end
    end

    class DogStatsdEventExpectation < DogStatsDExpectation
      # pass `title` as `name:`, `text` as `value:`
      def initialize(type:, **options)
        raise ArgumentError, 'type must be :_e (event)' unless type == :_e


        # # event params
        # {
        #   aggregation_key: nil,
        #   alert_type: nil,
        #   hostname: nil,
        #   priority: nil,
        #   source_type_name: nil,
        #   timestamp: nil,
        # }

        # # Superclass params
        # {
        #   client: StatsD.singleton_client,
        #   name:,
        #   no_prefix: false,
        #   sample_rate: nil,
        #   tags: nil,
        #   times: 1,
        #   type:,
        #   value: nil,
        # }

        raise NotImplementedError
      end
    end

    # FIXME: Add remaining fields described by https://docs.datadoghq.com/developers/dogstatsd/datagram_shell/?tab=servicechecks#events

    class DogStatsdServiceCheckExpectation < DogStatsDExpectation
      attr_accessor :message

      # TODO: Double check all params are supported by this
      def initialize(type:, message: nil, **options)
        raise ArgumentError, 'type must be :_sc (service check)' unless type == :_sc

        @message = message
        options[:value] = normalized_value_for_type(type, options[:value]) if options[:value]

        super(type: type, **options)
      end

      def normalized_value_for_type(type, value)
        return super unless type == :_sc

        # FIXME: Consolidate this somewhere
        return value if value.is_a?(Integer)
        { ok: 0, warning: 1, critical: 2, unknown: 3 }.fetch(value.to_sym)
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
    end
  end
end
