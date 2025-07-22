# frozen_string_literal: true

require "test_helper"

class DispatcherStatsTest < Minitest::Test
  include StatsD::Instrument::Assertions

  def test_maybe_flush
    stats = StatsD::Instrument::BatchedSink::DispatcherStats.new(0, "udp")

    stats.increment_synchronous_sends
    stats.increment_batched_sends(1, 1, 1)

    expectations = [
      StatsD::Instrument::Expectation.increment("statsd_instrument.batched_udp_sink.synchronous_sends", 1),
      StatsD::Instrument::Expectation.increment("statsd_instrument.batched_udp_sink.batched_sends", 1),
      StatsD::Instrument::Expectation.gauge("statsd_instrument.batched_udp_sink.avg_buffer_length", 1),
      StatsD::Instrument::Expectation.gauge("statsd_instrument.batched_udp_sink.avg_batched_packet_size", 1),
      StatsD::Instrument::Expectation.gauge("statsd_instrument.batched_udp_sink.avg_batch_length", 1),
    ]
    assert_statsd_expectations(expectations) { stats.maybe_flush! }
    assert_equal(0, stats.instance_variable_get(:@synchronous_sends))
    assert_equal(0, stats.instance_variable_get(:@batched_sends))
    assert_equal(0, stats.instance_variable_get(:@avg_buffer_length))
    assert_equal(0, stats.instance_variable_get(:@avg_batched_packet_size))
    assert_equal(0, stats.instance_variable_get(:@avg_batch_length))

    stats = StatsD::Instrument::BatchedSink::DispatcherStats.new(1, :udp)
    stats.increment_batched_sends(1, 1, 1)
    assert_no_statsd_calls { stats.maybe_flush! }
  end

  def test_calculations_are_correct
    stats = StatsD::Instrument::BatchedSink::DispatcherStats.new(0, :udp)

    5.times { stats.increment_synchronous_sends }
    assert_equal(5, stats.instance_variable_get(:@synchronous_sends))

    batches = [
      { buffer_len: 100, packet_size: 1472, batch_len: 10 },
      { buffer_len: 90,  packet_size: 1300, batch_len: 20 },
      { buffer_len: 110, packet_size: 1470, batch_len: 8  },
      { buffer_len: 500, packet_size: 1000, batch_len: 1  },
      { buffer_len: 100, packet_size: 30,   batch_len: 99 },
    ]
    batches.each do |batch|
      stats.increment_batched_sends(batch[:buffer_len], batch[:packet_size], batch[:batch_len])
    end
    assert_equal(batches.length, stats.instance_variable_get(:@batched_sends))
    assert_equal(
      batches.map do |b|
        b[:buffer_len]
      end.sum / batches.length,
      stats.instance_variable_get(:@avg_buffer_length),
    )
    assert_equal(
      batches.map do |b|
        b[:packet_size]
      end.sum / batches.length,
      stats.instance_variable_get(:@avg_batched_packet_size),
    )
    assert_equal(
      batches.map do |b|
        b[:batch_len]
      end.sum / batches.length,
      stats.instance_variable_get(:@avg_batch_length),
    )
  end
end
