# frozen_string_literal: true

module StatsD
  module Instrument
    class Sink
      class << self
        def for_addr(addr)
          # if addr is host:port
          if addr.include?(":")
            host, port_as_string = addr.split(":", 2)
            connection = UdpConnection.new(host, Integer(port_as_string))
            new(connection)
          else
            connection = UdsConnection.new(addr)
            new(connection)
          end
        end
      end

      FINALIZER = ->(object_id) do
        Thread.list.each do |thread|
          if (store = thread["StatsD::UDPSink"])
            store.delete(object_id)&.close
          end
        end
      end

      def initialize(connection = nil)
        ObjectSpace.define_finalizer(self, FINALIZER)
        @connection = connection
      end

      def sample?(sample_rate)
        sample_rate == 1.0 || rand < sample_rate
      end

      def <<(datagram)
        retried = false
        begin
          connection.send_datagram(datagram)
        rescue SocketError, IOError, SystemCallError => error
          StatsD.logger.debug do
            "[#{self.class.name}] [#{connection.class.name}] " \
              "Resetting connection because of #{error.class}: #{error.message}"
          end
          invalidate_connection
          if retried
            StatsD.logger.warn do
              "[#{self.class.name}] [#{connection.class.name}] " \
                "Events were dropped (after retrying) because of #{error.class}: #{error.message}. " \
                "Message size: #{datagram.bytesize} bytes."
            end
          else
            retried = true
            retry
          end
        end
        self
      end

      def flush(blocking: false)
        # noop
      end

      def connection_type
        connection.class.name
      end

      def connection
        thread_store[object_id] ||= @connection
      end

      def host
        connection.host
      end

      def port
        connection.port
      end

      private

      def invalidate_connection
        connection&.close
      end

      def thread_store
        Thread.current["StatsD::Sink"] ||= {}
      end
    end
  end
end
