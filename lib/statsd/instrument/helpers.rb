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
    end
  end
end
