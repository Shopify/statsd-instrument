# frozen_string_literal: true

module StatsD
  module Instrument
    module Helpers
      def capture_statsd_datagrams(client: nil, &block)
        client ||= StatsD.singleton_client
        client.capture(&block)
      end

      # For backwards compatibility
      alias_method :capture_statsd_calls, :capture_statsd_datagrams

      class << self
        def add_tag(tags, key, value)
          tags = tags.dup || {}

          if tags.is_a?(String)
            tags = tags.empty? ? "#{key}:#{value}" : "#{tags},#{key}:#{value}"
          elsif tags.is_a?(Array)
            tags << "#{key}:#{value}"
          elsif tags.is_a?(Hash)
            tags[key] = value
          else
            raise ArgumentError, "add_tag only supports string, array or hash, #{tags.class} provided"
          end

          tags
        end

        def prefix_metric(metric_name, client: nil)
          client ||= StatsD.singleton_client
          client&.prefix ? "#{client.prefix}.#{metric_name}" : metric_name
        end

        def prefixed_metric?(metric_name, client: nil)
          client ||= StatsD.singleton_client
          return false unless client&.prefix

          metric_name =~ /\A#{Regexp.escape(client.prefix)}\./
        end
      end
    end
  end
end
