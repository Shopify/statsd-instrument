# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class ThreadedUDPSink
      def self.for_addr(addr)
        host, port_as_string = addr.split(":", 2)
        new(host, Integer(port_as_string))
      end

      class Dispatcher
        class << self
          def finalizer(instance)
            Proc.new { instance.stop }
          end
        end

        def initialize(host, port, queue)
          @host = host
          @port = port
          @queue = queue
          @socket = nil
          @thread = nil
          ObjectSpace.define_finalizer(self, self.class.finalizer(self))
        end

        def start
          @thread = Thread.new { dispatcher_loop }
          self
        end

        def clear
          @queue.clear
        end

        def stop
          @queue.close
          begin
            @thread.join(2)
          rescue ThreadError => e
            # We did our best
          end
        end

        private

        def dispatcher_loop
          while datagram = @queue.pop(false)
            begin
              socket.send(datagram, 0)
            rescue SocketError, IOError, SystemCallError => e
              # TODO: log?
              invalidate_socket
            end
          end
        ensure
          @socket&.flush
        end

        def socket
          if @socket.nil?
            @socket = UDPSocket.new
            @socket.connect(@host, @port)
          end
          @socket
        end

        def invalidate_socket
          @socket&.flush
          @socket = nil
        end
      end

      attr_reader :host, :port

      def initialize(host, port)
        @host = host
        @port = port
        spawn_dispatcher
      end

      def sample?(sample_rate)
        sample_rate == 1 || rand < sample_rate
      end

      def <<(datagram)
        @queue << datagram
        self
      end

      def after_fork
        @dispatcher.clear
        spawn_dispatcher
      end

      def addr
        "#{host}:#{port}"
      end

      private

      def spawn_dispatcher
        @queue = Queue.new
        @dispatcher = Dispatcher.new(host, port, @queue).start
      end
    end
  end
end
