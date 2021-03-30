# frozen_string_literal: true

require 'objspace'
require 'thread'

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class UDPSink
      def self.for_addr(addr)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string))
      end

      class Dispatcher
        def initialize(host, port, queue)
          @host = host
          @port = port
          @queue = queue
          @socket = nil
          @thread = nil
          ObjectSpace.define_finalizer(self, Proc.new { |o| o.stop })
        end

        def start
          @thread = Thread.new { dispatcher_loop }
          self
        end

        def stop
          @queue.close
          @thread.join(0.1)
        rescue ThreadError
        end

        private
        def dispatcher_loop
          loop do
            datagram = @queue.pop(false)
            begin
              socket.send(datagram, 0)
            rescue ThreadError
              socket.send(datagram, 0)
            rescue SocketError, IOError, SystemCallError
              # TODO: log?
              invalidate_socket
            end
          end
        end

        def socket
          if @socket.nil?
            @socket = UDPSocket.new
            @socket.connect(@host, @port)
          end
          @socket
        end

        def invalidate_socket
          @socket = nil
        end
      end

      attr_reader :host, :port

      def initialize(host, port)
        @host = host
        @port = port
        @queue = Queue.new
        @dispatcher = Dispatcher.new(host, port, @queue).start
      end

      def sample?(sample_rate)
        sample_rate == 1 || rand < sample_rate
      end

      def <<(datagram)
        @queue << datagram
        self
      end

      def addr
        "#{host}:#{port}"
      end
    end
  end
end
