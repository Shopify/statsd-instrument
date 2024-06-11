# frozen_string_literal: true

module StatsD
  module Instrument
    # This middleware is used to flush the {StatsD::Instrument::Instrumenter} after the request
    # has been processed.
    class FlushingMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        env["rack.after_reply"] ||= []
        env["rack.after_reply"] << -> do
          StatsD.singleton_client.force_flush
        rescue => e
          Rails.logger.error("Error flushing StatsD sink #{e.message}")
        end

        @app.call(env)
      end
    end
  end
end
