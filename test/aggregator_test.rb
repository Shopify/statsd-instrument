# frozen_string_literal: true

require "test_helper"

class AggregatorTest < Minitest::Test
  class CaptureLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    [:debug, :info, :warn, :error, :fatal].each do |severity|
      define_method(severity) do |message = nil, &block|
        message = block.call if message.nil? && block
        @messages << { severity: severity, message: message }
      end
    end
  end

  def setup
    @logger = CaptureLogger.new
    @old_logger = StatsD.logger
    StatsD.logger = @logger

    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @subject = StatsD::Instrument::Aggregator.new(
      @sink, StatsD::Instrument::DatagramBuilder, nil, [], flush_interval: 0.1
    )
  end

  def teardown
    @sink.clear
    StatsD.logger = @old_logger
  end

  def test_increment_simple
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(1.0, datagram.sample_rate)
    assert_equal(["foo:bar"], datagram.tags)
  end

  def test_distribution_simple
    @subject.aggregate_timing("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("foo", 100, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value.size)
    assert_equal([1.0, 100.0], datagram.value)
  end

  def test_timing_sampling_scaling
    @subject.aggregate_timing("timing.sampled", 60.0, sample_rate: 0.01)
    @subject.aggregate_timing("timing.sampled", 80.0, sample_rate: 0.01)
    @subject.aggregate_timing("timing.unsampled", 60.0, sample_rate: 1.0)

    @subject.flush

    assert_equal(2, @sink.datagrams.size)

    sampled_datagram = @sink.datagrams.find { |d| d.name == "timing.sampled" }
    assert_equal([60.0, 80.0], sampled_datagram.value)
    assert_equal(0.01, sampled_datagram.sample_rate)
    assert_equal("timing.sampled:60.0:80.0|d|@0.01", sampled_datagram.source)

    unsampled_datagram = @sink.datagrams.find { |d| d.name == "timing.unsampled" }
    assert_equal(60.0, unsampled_datagram.value)
  end

  def test_mixed_type_timings
    @subject.aggregate_timing("foo_ms", 1, tags: { foo: "bar" }, type: :ms)
    @subject.aggregate_timing("foo_ms", 100, tags: { foo: "bar" }, type: :ms)

    @subject.aggregate_timing("foo_d", 100, tags: { foo: "bar" }, type: :d)
    @subject.aggregate_timing("foo_d", 120, tags: { foo: "bar" }, type: :d)

    @subject.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_ms" }.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_d" }.size)
    assert_equal("ms", @sink.datagrams.find { |d| d.name == "foo_ms" }.type.to_s)
    assert_equal("d", @sink.datagrams.find { |d| d.name == "foo_d" }.type.to_s)
  end

  def test_gauge_simple
    @subject.gauge("foo", 1, tags: { foo: "bar" })
    @subject.gauge("foo", 100, tags: { foo: "bar" })
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(100, datagram.value)
    assert_equal(:g, datagram.type)
  end

  def test_increment_with_tags_in_different_orders
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, tags: ["tag2:val2", "tag1:val1"])
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
  end

  def test_increment_with_different_tag_values
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 1, tags: { tag1: "val1", tag2: "val2" })

    @subject.increment("bar")
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
    assert_equal(2, @sink.datagrams.size)
    assert_equal(["tag1:val1", "tag2:val2"], @sink.datagrams.first.tags)
  end

  def test_increment_with_different_metric_names
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("bar", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(1, @sink.datagrams.find { |d| d.name == "foo" }.value)
    assert_equal(1, @sink.datagrams.find { |d| d.name == "bar" }.value)
  end

  def test_increment_with_different_values
    @subject.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("foo", 2, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(3, @sink.datagrams.first.value)
  end

  def test_send_mixed_types_will_pass_through
    @subject.increment("test_counter", 1, tags: ["tag1:val1", "tag2:val2"])
    @subject.aggregate_timing("test_counter", 100, tags: ["tag1:val1", "tag2:val2"])

    @subject.gauge("test_gauge", 100, tags: ["tag1:val1", "tag2:val2"])
    @subject.increment("test_gauge", 1, tags: ["tag1:val1", "tag2:val2"])

    @subject.aggregate_timing("test_timing", 100, tags: ["tag1:val1", "tag2:val2"])
    @subject.gauge("test_timing", 100, tags: ["tag1:val1", "tag2:val2"])
    @subject.flush

    assert_equal(6, @sink.datagrams.size)

    assert_equal(2, @sink.datagrams.filter { |d| d.name == "test_counter" }.size)
    assert_equal(2, @sink.datagrams.filter { |d| d.name == "test_gauge" }.size)
    assert_equal(2, @sink.datagrams.filter { |d| d.name == "test_timing" }.size)

    assert_equal(:d, @sink.datagrams.find { |d| d.name == "test_timing" }.type)
    assert_equal(:g, @sink.datagrams.find { |d| d.name == "test_gauge" }.type)
    assert_equal(:c, @sink.datagrams.find { |d| d.name == "test_counter" }.type)
  end

  def test_with_prefix
    aggregator = StatsD::Instrument::Aggregator.new(@sink, StatsD::Instrument::DatagramBuilder, "MyApp", [])

    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])
    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"])

    aggregator.increment("foo", 1, tags: ["tag1:val1", "tag2:val2"], no_prefix: true)
    aggregator.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal("MyApp.foo", @sink.datagrams.first.name)
    assert_equal(2, @sink.datagrams.first.value)

    assert_equal("foo", @sink.datagrams.last.name)
    assert_equal(1, @sink.datagrams.last.value)
  end

  def test_synchronous_operation_on_thread_failure
    # Force thread_healthcheck to return false
    @subject.stubs(:thread_healthcheck).returns(false)

    # Stub methods on @aggregation_state to ensure they are not called
    aggregation_state = @subject.instance_variable_get(:@aggregation_state)
    aggregation_state.stubs(:[]=).never
    aggregation_state.stubs(:clear).never

    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("bar", 100, tags: { foo: "bar" })
    @subject.gauge("baz", 100, tags: { foo: "bar" })

    # Verify metrics were sent immediately
    assert_equal(3, @sink.datagrams.size)

    counter_datagram = @sink.datagrams.find { |d| d.name == "foo" }
    assert_equal(1, counter_datagram.value)
    assert_equal(["foo:bar"], counter_datagram.tags)

    timing_datagram = @sink.datagrams.find { |d| d.name == "bar" }
    assert_equal([100.0], [timing_datagram.value])
    assert_equal(["foo:bar"], timing_datagram.tags)

    gauge_datagram = @sink.datagrams.find { |d| d.name == "baz" }
    assert_equal(100, gauge_datagram.value)
    assert_equal(["foo:bar"], gauge_datagram.tags)

    # Additional metrics should also go through synchronously
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("bar", 200, tags: { foo: "bar" }, sample_rate: 0.5)

    # Verify new metrics were also sent immediately
    assert_equal(5, @sink.datagrams.size)

    counter_datagram = @sink.datagrams.select { |d| d.name == "foo" }.last
    assert_equal(1, counter_datagram.value)
    assert_equal(["foo:bar"], counter_datagram.tags)

    timing_datagram = @sink.datagrams.select { |d| d.name == "bar" }.last
    assert_equal([200.0], [timing_datagram.value])
    assert_equal(["foo:bar"], timing_datagram.tags)
    assert_equal(0.5, timing_datagram.sample_rate)

    # undo the stubbing
    @subject.unstub(:thread_healthcheck)
  end

  def test_recreate_thread_after_fork
    skip("#{RUBY_ENGINE} not supported for this test. Reason: fork()") if RUBY_ENGINE != "ruby"
    # Record initial metrics
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("bar", 100, tags: { foo: "bar" })

    # kill the flush thread
    @subject.instance_variable_get(:@flush_thread).kill

    # Fork the process
    pid = Process.fork do
      # In forked process, send more metrics
      @subject.increment("foo", 2, tags: { foo: "bar" })
      @subject.aggregate_timing("bar", 200, tags: { foo: "bar" })
      @subject.flush

      assert_equal(2, @sink.datagrams.size)
      exit!
    end

    # Wait for forked process to complete
    Process.wait(pid)

    # Send metrics in parent process
    @subject.increment("foo", 3, tags: { foo: "bar" })
    @subject.aggregate_timing("bar", 300, tags: { foo: "bar" })
    @subject.flush

    assert_equal(2, @sink.datagrams.size)

    # Verify metrics were properly aggregated in parent process
    counter_datagrams = @sink.datagrams.select { |d| d.name == "foo" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "bar" }

    assert_equal(1, counter_datagrams.size)
    assert_equal(1, timing_datagrams.size)

    # Aggregate despite fork
    assert_equal(4, counter_datagrams.last.value)
    assert_equal([100.0, 300.0], timing_datagrams.last.value)
  end

  def test_race_condition_during_forking
    skip("#{RUBY_ENGINE} not supported for this test. Reason: fork()") if RUBY_ENGINE != "ruby"
    # Record initial metrics
    @subject.increment("before_fork.count", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("before_fork.timing", 100, tags: { foo: "bar" })

    # Fork the process
    pid = Process.fork do
      # In forked process, send more metrics
      @subject.increment("in_child.count", 2, tags: { foo: "bar" })
      @subject.aggregate_timing("in_child.timing", 200, tags: { foo: "bar" })

      # Simulate thread waiting for flush
      sleep(0.1)
      @subject.flush

      assert_equal(2, @sink.datagrams.size)
      exit!
    end

    # Call flush concurrently in parent process
    @subject.flush

    # Wait for forked process to complete
    Process.wait(pid)

    # Send metrics in parent process
    @subject.increment("after_fork.count", 3, tags: { foo: "bar" })
    @subject.aggregate_timing("after_fork.timing", 300, tags: { foo: "bar" })
    @subject.flush

    assert_equal(4, @sink.datagrams.size)

    # Verify metrics were properly aggregated in parent process
    counter_datagrams = @sink.datagrams.select { |d| d.name == "before_fork.count" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "before_fork.count" }
    assert_equal(
      1,
      counter_datagrams.size,
      "Expected to find 1 counter datagram. Datagrams: #{@sink.datagrams.inspect}",
    )
    assert_equal(1, timing_datagrams.size)

    # After fork metrics
    counter_datagrams = @sink.datagrams.select { |d| d.name == "after_fork.count" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "after_fork.count" }
    assert_equal(1, counter_datagrams.size)
    assert_equal(1, timing_datagrams.size)
  end

  def test_finalizer_flushes_pending_metrics
    @subject.increment("foo", 1, tags: { foo: "bar" })
    @subject.aggregate_timing("bar", 100, tags: { foo: "bar" })
    @subject.gauge("baz", 100, tags: { foo: "bar" })
    @subject.aggregate_timing("sampled_timing", 100, tags: { foo: "bar" }, sample_rate: 0.01)

    # Manually trigger the finalizer
    finalizer = StatsD::Instrument::Aggregator.finalize(
      @subject.instance_variable_get(:@aggregation_state),
      @subject.instance_variable_get(:@sink),
      @subject.instance_variable_get(:@datagram_builders),
      StatsD::Instrument::DatagramBuilder,
      [],
    )
    finalizer.call

    # Verify that all pending metrics are sent
    assert_equal(4, @sink.datagrams.size)

    counter_datagram = @sink.datagrams.find { |d| d.name == "foo" }
    assert_equal(1, counter_datagram.value)
    assert_equal(["foo:bar"], counter_datagram.tags)

    timing_datagram = @sink.datagrams.find { |d| d.name == "bar" }
    assert_equal([100.0], [timing_datagram.value])
    assert_equal(["foo:bar"], timing_datagram.tags)

    gauge_datagram = @sink.datagrams.find { |d| d.name == "baz" }
    assert_equal(100, gauge_datagram.value)
    assert_equal(["foo:bar"], gauge_datagram.tags)

    sampled_timing_datagram = @sink.datagrams.find { |d| d.name == "sampled_timing" }
    assert_equal(100.0, sampled_timing_datagram.value)
    assert_equal(0.01, sampled_timing_datagram.sample_rate)
  end

  def test_signal_trap_context_fallback_to_direct_writes
    skip("#{RUBY_ENGINE} not supported for this test. Reason: signal handling") if RUBY_ENGINE != "ruby"

    signal_received = false
    metrics_sent_in_trap = []

    old_trap = Signal.trap("USR1") do
      signal_received = true
      # These operations should now fall back to direct writes
      @subject.increment("trap_counter", 1)
      @subject.gauge("trap_gauge", 42)
      @subject.aggregate_timing("trap_timing", 100)

      metrics_sent_in_trap = @sink.datagrams.map(&:name)
    end

    @sink.clear

    Process.kill("USR1", Process.pid)

    sleep(0.1)

    assert(signal_received, "Signal should have been received")

    assert_includes(metrics_sent_in_trap, "trap_counter")
    assert_includes(metrics_sent_in_trap, "trap_gauge")
    assert_includes(metrics_sent_in_trap, "trap_timing")

    counter_datagram = @sink.datagrams.find { |d| d.name == "trap_counter" }
    assert_equal(1, counter_datagram.value)

    gauge_datagram = @sink.datagrams.find { |d| d.name == "trap_gauge" }
    assert_equal(42, gauge_datagram.value)

    timing_datagram = @sink.datagrams.find { |d| d.name == "trap_timing" }
    assert_equal([100.0], [timing_datagram.value].flatten)

    debug_messages = @logger.messages.select { |m| m[:severity] == :debug }
    assert(
      debug_messages.any? { |m| m[:message].include?("In trap context, falling back to direct writes") },
      "Expected debug message about trap context fallback",
    )
  ensure
    Signal.trap("USR1", old_trap || "DEFAULT")
  end
end
