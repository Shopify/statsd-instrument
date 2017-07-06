require 'test_helper'

class UDPBackendTest < Minitest::Test
  def setup
    StatsD.stubs(:backend).returns(@backend = StatsD::Instrument::Backends::UDPBackend.new)
    @backend.stubs(:rand).returns(0.0)

    UDPSocket.stubs(:new).returns(@socket = mock('socket'))
    @socket.stubs(:connect)
    @socket.stubs(:send).returns(1)

    StatsD.stubs(:logger).returns(@logger = mock('logger'))
  end

  def test_changing_host_or_port_should_create_new_socket
    @socket.expects(:connect).with('localhost', 1234).once
    @socket.expects(:connect).with('localhost', 2345).once
    @socket.expects(:connect).with('127.0.0.1', 2345).once

    @backend.server = "localhost:1234"
    @backend.socket

    @backend.port = 2345
    @backend.socket

    @backend.host = '127.0.0.1'
    @backend.socket
  end

  def test_collect_respects_sampling_rate
    @socket.expects(:send).once.returns(1)
    metric = StatsD::Instrument::Metric.new(type: :c, name: 'test', sample_rate: 0.5)

    @backend.stubs(:rand).returns(0.4)
    @backend.collect_metric(metric)

    @backend.stubs(:rand).returns(0.6)
    @backend.collect_metric(metric)
  end

  def test_support_counter_syntax
    @backend.expects(:write_packet).with('counter:1|c').once
    StatsD.increment('counter', sample_rate: 1.0)

    @backend.expects(:write_packet).with('counter:1|c|@0.5').once
    StatsD.increment('counter', sample_rate: 0.5)
  end

  def test_supports_gauge_syntax
    @backend.expects(:write_packet).with('fooy:1.23|g')
    StatsD.gauge('fooy', 1.23)

    @backend.expects(:write_packet).with('fooy:42|g|@0.01')
    StatsD.gauge('fooy', 42, sample_rate: 0.01)
  end

  def test_supports_set_syntax
    @backend.expects(:write_packet).with('unique:10.0.0.10|s')
    StatsD.set('unique', '10.0.0.10')

    @backend.expects(:write_packet).with('unique:10.0.0.10|s|@0.01')
    StatsD.set('unique', '10.0.0.10', sample_rate: 0.01)
  end

  def test_support_measure_syntax
    @backend.expects(:write_packet).with('duration:1.23|ms')
    StatsD.measure('duration', 1.23)

    @backend.expects(:write_packet).with('duration:0.42|ms|@0.01')
    StatsD.measure('duration', 0.42, sample_rate: 0.01)
  end

  def test_histogram_syntax_on_datadog
    @backend.implementation = :datadog
    @backend.expects(:write_packet).with('fooh:42.4|h')
    StatsD.histogram('fooh', 42.4)
  end

  def test_histogram_warns_if_not_using_datadog
    @backend.implementation = :other
    @backend.expects(:write_packet).never
    @logger.expects(:warn)
    StatsD.histogram('fooh', 42.4)
  end

  def test_supports_key_value_syntax_on_statsite
    @backend.implementation = :statsite
    @backend.expects(:write_packet).with("fooy:42|kv\n")
    StatsD.key_value('fooy', 42)
  end

  def test_supports_key_value_with_timestamp_on_statsite
    @backend.implementation = :statsite
    @backend.expects(:write_packet).with("fooy:42|kv|@123456\n")
    StatsD.key_value('fooy', 42, 123456)
  end

  def test_warn_when_using_key_value_and_not_on_statsite
    @backend.implementation = :other
    @backend.expects(:write_packet).never
    @logger.expects(:warn)
    StatsD.key_value('fookv', 3.33)
  end

  def test_support_tags_syntax_on_datadog
    @backend.implementation = :datadog
    @backend.expects(:write_packet).with("fooc:3|c|#topic:foo,bar")
    StatsD.increment('fooc', 3, tags: ['topic:foo', 'bar'])
  end

  def test_warn_when_using_tags_and_not_on_datadog
    @backend.implementation = :other
    @backend.expects(:write_packet).with("fooc:1|c")
    @logger.expects(:warn)
    StatsD.increment('fooc', tags: ['ignored'])
  end

  def test_socket_error_should_not_raise_but_log
    @socket.stubs(:connect).raises(SocketError)
    @logger.expects(:error)
    StatsD.increment('fail')
  end

  def test_system_call_error_should_not_raise_but_log
    @socket.stubs(:send).raises(Errno::ETIMEDOUT)
    @logger.expects(:error)
    StatsD.increment('fail')
  end

  def test_io_error_should_not_raise_but_log
    @socket.stubs(:send).raises(IOError)
    @logger.expects(:error)
    StatsD.increment('fail')
  end

  def test_synchronize_in_exit_handler_handles_thread_error_and_exits_cleanly
    pid = fork do
      Signal.trap('TERM') do
        $sent_packet = false

        class << @backend.socket
          def send(command, *args)
            $sent_packet = true if command == 'exiting:1|c'
            command.length
          end
        end

        StatsD.increment('exiting')
        Process.exit!($sent_packet)
      end

      sleep 100
    end

    Process.kill('TERM', pid)
    Process.waitpid(pid)

    assert $?.success?, 'socket did not write on exit'
  end
end
