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

      attr_accessor :hostname, :timestamp

      def initialize(sample_rate: nil, hostname: nil, timestamp: nil, **options)
        raise ArgumentError, 'sample_rate not supported' if sample_rate

        @hostname = hostname
        @timestamp = timestamp&.to_i

        super(**options)
      end

      def matches(actual_metric)
        return false if hostname && hostname != actual_metric.hostname
        return false if timestamp && timestamp != actual_metric.timestamp

        super
      end
    end

    class DogStatsdEventExpectation < DogStatsDExpectation
      attr_accessor :aggregation_key, :alert_type, :priority, :source_type_name

      def initialize(type:, name:, aggregation_key: nil, alert_type: nil, priority: nil, source_type_name: nil, **options)
        raise ArgumentError, 'type must be :_e (event)' unless type == :_e
        raise ArgumentError, 'use `name:` to specify title' if options.key?(:title)
        raise ArgumentError, 'use `value:` to specify text' if options.key?(:text)

        @aggregation_key = aggregation_key
        @alert_type = alert_type
        @priority = priority
        @source_type_name = source_type_name

        super(
          type: type,
          # event name/title is normalize in identically to value/text
          name: normalized_value_for_type(type, name),
          **options
        )
      end

      def normalized_value_for_type(type, value)
        return super unless type == :_e
        return value unless value.present?

        value.gsub("\n", '\n')
      end

      def matches(actual_metric)
        return false if aggregation_key && aggregation_key != actual_metric.aggregation_key
        return false if alert_type && alert_type != actual_metric.alert_type
        return false if priority && priority != actual_metric.priority
        return false if source_type_name && source_type_name != actual_metric.source_type_name

        super
      end

      def to_s
        datagram = +"_e{#{name.length},#{value&.length || '<anything>'}}:#{name}|#{value || '<anything>'}"
        datagram << "|h:#{hostname}" if hostname
        datagram << "|d:#{timestamp}" if timestamp
        datagram << "|k:#{aggregation_key}" if aggregation_key
        datagram << "|p:#{priority}" if priority
        datagram << "|s:#{source_type_name}" if source_type_name
        datagram << "|t:#{alert_type}" if alert_type
        datagram << "|##{tags.join(',')}" unless tags.empty?
        datagram
      end
    end

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

      def to_s
        datagram = +"_sc|#{name}|#{value || '<anything>'}"
        datagram << "|h:#{hostname}" if hostname
        datagram << "|d:#{timestamp}" if timestamp
        datagram << "|##{tags.join(',')}" unless tags.empty?
        datagram << "|m:#{message}" if message
        datagram
      end
    end
  end
end
