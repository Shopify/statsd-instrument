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
    @subject.instance_variable_get(:@flush_thread)&.kill
    @sink.clear
    StatsD.logger = @old_logger
  end

  def test_increment_simple
    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value)
    assert_equal(1.0, datagram.sample_rate)
    assert_equal(["foo:bar"], datagram.tags)
  end

  def test_increment_with_sample_rate
    @subject.increment("counter.sampled", 1, ["foo:bar"], false, 0.5)
    @subject.increment("counter.sampled", 2, ["foo:bar"], false, 0.5)
    @subject.increment("counter.unsampled", 1, ["foo:bar"], false, 1.0)
    @subject.flush

    assert_equal(2, @sink.datagrams.size)

    sampled_datagram = @sink.datagrams.find { |d| d.name == "counter.sampled" }
    assert_equal(3, sampled_datagram.value) # 1 + 2
    assert_equal(0.5, sampled_datagram.sample_rate)
    assert_includes(sampled_datagram.source, "|@0.5")

    unsampled_datagram = @sink.datagrams.find { |d| d.name == "counter.unsampled" }
    assert_equal(1, unsampled_datagram.value)
    assert_equal(1.0, unsampled_datagram.sample_rate)
    refute_includes(unsampled_datagram.source, "|@")
  end

  def test_increment_different_sample_rates_create_different_aggregation_keys
    @subject.increment("counter", 1, [], false, 0.5)
    @subject.increment("counter", 2, [], false, 0.5)
    @subject.increment("counter", 10, [], false, 0.1)
    @subject.increment("counter", 20, [], false, 0.1)
    @subject.flush

    assert_equal(2, @sink.datagrams.size)

    datagram_05 = @sink.datagrams.find { |d| d.sample_rate == 0.5 }
    assert_equal(3, datagram_05.value) # 1 + 2

    datagram_01 = @sink.datagrams.find { |d| d.sample_rate == 0.1 }
    assert_equal(30, datagram_01.value) # 10 + 20
  end

  def test_distribution_simple
    @subject.aggregate_timing("foo", 1, ["foo:bar"], false, :d, 1.0)
    @subject.aggregate_timing("foo", 100, ["foo:bar"], false, :d, 1.0)
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(2, datagram.value.size)
    assert_equal([1.0, 100.0], datagram.value)
  end

  def test_timing_sampling_scaling
    @subject.aggregate_timing("timing.sampled", 60.0, [], false, :d, 0.01)
    @subject.aggregate_timing("timing.sampled", 80.0, [], false, :d, 0.01)
    @subject.aggregate_timing("timing.unsampled", 60.0, [], false, :d, 1.0)

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
    @subject.aggregate_timing("foo_ms", 1, ["foo:bar"], false, :ms, 1.0)
    @subject.aggregate_timing("foo_ms", 100, ["foo:bar"], false, :ms, 1.0)

    @subject.aggregate_timing("foo_d", 100, ["foo:bar"], false, :d, 1.0)
    @subject.aggregate_timing("foo_d", 120, ["foo:bar"], false, :d, 1.0)

    @subject.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_ms" }.size)
    assert_equal(1, @sink.datagrams.filter { |d| d.name == "foo_d" }.size)
    assert_equal("ms", @sink.datagrams.find { |d| d.name == "foo_ms" }.type.to_s)
    assert_equal("d", @sink.datagrams.find { |d| d.name == "foo_d" }.type.to_s)
  end

  def test_gauge_simple
    @subject.gauge("foo", 1, ["foo:bar"], false)
    @subject.gauge("foo", 100, ["foo:bar"], false)
    @subject.flush

    datagram = @sink.datagrams.first
    assert_equal("foo", datagram.name)
    assert_equal(100, datagram.value)
    assert_equal(:g, datagram.type)
  end

  def test_increment_with_tags_in_different_orders
    @subject.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.increment("foo", 1, ["tag2:val2", "tag1:val1"], false, 1.0)
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
  end

  def test_unsorted_tags_in_different_orders_aggregate_separately
    aggregator = unsorted_aggregator
    aggregator.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    aggregator.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    aggregator.increment("foo", 1, ["tag2:val2", "tag1:val1"], false, 1.0)
    aggregator.flush

    assert_equal(
      ["foo:2|c|#tag1:val1,tag2:val2", "foo:1|c|#tag2:val2,tag1:val1"],
      @sink.datagrams.map(&:source),
    )
  ensure
    aggregator&.instance_variable_get(:@flush_thread)&.kill
  end

  def test_unsorted_tags_keep_hash_order
    aggregator = unsorted_aggregator
    aggregator.aggregate_timing("foo", 1, { tag2: "val2", tag1: "val1" }, false, :d, 1.0)
    aggregator.aggregate_timing("foo", 2, ["tag2:val2", "tag1:val1"], false, :d, 1.0)
    aggregator.gauge("bar", 3, { tag2: "val2", tag1: "val1" }, false)
    aggregator.flush

    assert_equal(
      ["foo:1:2|d|#tag2:val2,tag1:val1", "bar:3|g|#tag2:val2,tag1:val1"],
      @sink.datagrams.map(&:source),
    )
  ensure
    aggregator&.instance_variable_get(:@flush_thread)&.kill
  end

  def test_unsorted_tags_do_not_mutate_the_caller_tags
    aggregator = unsorted_aggregator
    tags = ["tag2:val2", "tag1:val1"].freeze
    aggregator.increment("foo", 1, tags, false, 1.0)
    aggregator.flush

    assert_equal(["tag2:val2", "tag1:val1"], tags)
    assert_equal("foo:1|c|#tag2:val2,tag1:val1", @sink.datagrams.first.source)
  ensure
    aggregator&.instance_variable_get(:@flush_thread)&.kill
  end

  def test_increment_with_different_tag_values
    @subject.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.increment("foo", 1, { tag1: "val1", tag2: "val2" }, false, 1.0)

    @subject.increment("bar", 1, [], false, 1.0)
    @subject.flush

    assert_equal(2, @sink.datagrams.first.value)
    assert_equal(2, @sink.datagrams.size)
    assert_equal(["tag1:val1", "tag2:val2"], @sink.datagrams.first.tags)
  end

  def test_increment_with_different_metric_names
    @subject.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.increment("bar", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.flush

    assert_equal(1, @sink.datagrams.find { |d| d.name == "foo" }.value)
    assert_equal(1, @sink.datagrams.find { |d| d.name == "bar" }.value)
  end

  def test_increment_with_different_values
    @subject.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.increment("foo", 2, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.flush

    assert_equal(3, @sink.datagrams.first.value)
  end

  def test_send_mixed_types_will_pass_through
    @subject.increment("test_counter", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    @subject.aggregate_timing("test_counter", 100, ["tag1:val1", "tag2:val2"], false, :d, 1.0)

    @subject.gauge("test_gauge", 100, ["tag1:val1", "tag2:val2"], false)
    @subject.increment("test_gauge", 1, ["tag1:val1", "tag2:val2"], false, 1.0)

    @subject.aggregate_timing("test_timing", 100, ["tag1:val1", "tag2:val2"], false, :d, 1.0)
    @subject.gauge("test_timing", 100, ["tag1:val1", "tag2:val2"], false)
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

    aggregator.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)
    aggregator.increment("foo", 1, ["tag1:val1", "tag2:val2"], false, 1.0)

    aggregator.increment("foo", 1, ["tag1:val1", "tag2:val2"], true, 1.0)
    aggregator.flush

    assert_equal(2, @sink.datagrams.size)
    assert_equal("MyApp.foo", @sink.datagrams.first.name)
    assert_equal(2, @sink.datagrams.first.value)

    assert_equal("foo", @sink.datagrams.last.name)
    assert_equal(1, @sink.datagrams.last.value)
  end

  def test_finalizer_with_prefix
    aggregator = StatsD::Instrument::Aggregator.new(@sink, StatsD::Instrument::DatagramBuilder, "MyApp", [])

    aggregator.increment("foo", 1, [], false, 1.0)
    aggregator.increment("bar", 1, [], true, 1.0)

    finalizer = StatsD::Instrument::Aggregator.finalize(
      aggregator.instance_variable_get(:@finalizer),
    )
    finalizer.call

    assert_equal(2, @sink.datagrams.size)

    prefixed_datagram = @sink.datagrams.find { |d| d.name == "MyApp.foo" }
    refute_nil(prefixed_datagram, "Expected to find datagram with prefix 'MyApp.foo'")
    assert_equal(1, prefixed_datagram.value)

    unprefixed_datagram = @sink.datagrams.find { |d| d.name == "bar" }
    refute_nil(unprefixed_datagram, "Expected to find datagram without prefix 'bar'")
    assert_equal(1, unprefixed_datagram.value)
  end

  def test_synchronous_operation_on_thread_failure
    @subject.stubs(:thread_healthcheck).returns(false)

    aggregation_state = @subject.instance_variable_get(:@aggregation_state)
    aggregation_state.stubs(:[]=).never

    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("bar", 100, ["foo:bar"], false, :d, 1.0)
    @subject.gauge("baz", 100, ["foo:bar"], false)

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

    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("bar", 200, ["foo:bar"], false, :d, 0.5)

    assert_equal(5, @sink.datagrams.size)

    counter_datagram = @sink.datagrams.select { |d| d.name == "foo" }.last
    assert_equal(1, counter_datagram.value)
    assert_equal(["foo:bar"], counter_datagram.tags)

    timing_datagram = @sink.datagrams.select { |d| d.name == "bar" }.last
    assert_equal([200.0], [timing_datagram.value])
    assert_equal(["foo:bar"], timing_datagram.tags)
    assert_equal(0.5, timing_datagram.sample_rate)

    after_aggregation_state = @subject.instance_variable_get(:@aggregation_state)
    assert_same(after_aggregation_state, aggregation_state)

    @subject.unstub(:thread_healthcheck)
  end

  def test_recreate_thread_after_fork
    skip("#{RUBY_ENGINE} not supported for this test. Reason: fork()") if RUBY_ENGINE != "ruby"
    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("bar", 100, ["foo:bar"], false, :d, 1.0)

    @subject.instance_variable_get(:@flush_thread).kill

    pid = Process.fork do
      @subject.increment("foo", 2, ["foo:bar"], false, 1.0)
      @subject.aggregate_timing("bar", 200, ["foo:bar"], false, :d, 1.0)
      @subject.flush

      assert_equal(2, @sink.datagrams.size)
      exit!
    end

    Process.wait(pid)

    @subject.increment("foo", 3, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("bar", 300, ["foo:bar"], false, :d, 1.0)
    @subject.flush

    assert_equal(2, @sink.datagrams.size)

    counter_datagrams = @sink.datagrams.select { |d| d.name == "foo" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "bar" }

    assert_equal(1, counter_datagrams.size)
    assert_equal(1, timing_datagrams.size)

    assert_equal(4, counter_datagrams.last.value)
    assert_equal([100.0, 300.0], timing_datagrams.last.value)
  end

  def test_race_condition_during_forking
    skip("#{RUBY_ENGINE} not supported for this test. Reason: fork()") if RUBY_ENGINE != "ruby"
    @subject.increment("before_fork.count", 1, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("before_fork.timing", 100, ["foo:bar"], false, :d, 1.0)

    pid = Process.fork do
      @subject.increment("in_child.count", 2, ["foo:bar"], false, 1.0)
      @subject.aggregate_timing("in_child.timing", 200, ["foo:bar"], false, :d, 1.0)

      sleep(0.1)
      @subject.flush

      assert_equal(2, @sink.datagrams.size)
      exit!
    end

    @subject.flush

    Process.wait(pid)

    @subject.increment("after_fork.count", 3, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("after_fork.timing", 300, ["foo:bar"], false, :d, 1.0)
    @subject.flush

    assert_equal(4, @sink.datagrams.size)

    counter_datagrams = @sink.datagrams.select { |d| d.name == "before_fork.count" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "before_fork.count" }
    assert_equal(
      1,
      counter_datagrams.size,
      "Expected to find 1 counter datagram. Datagrams: #{@sink.datagrams.inspect}",
    )
    assert_equal(1, timing_datagrams.size)

    counter_datagrams = @sink.datagrams.select { |d| d.name == "after_fork.count" }
    timing_datagrams = @sink.datagrams.select { |d| d.name == "after_fork.count" }
    assert_equal(1, counter_datagrams.size)
    assert_equal(1, timing_datagrams.size)
  end

  def test_finalizer_flushes_pending_metrics
    @subject.increment("foo", 1, ["foo:bar"], false, 1.0)
    @subject.aggregate_timing("bar", 100, ["foo:bar"], false, :d, 1.0)
    @subject.gauge("baz", 100, ["foo:bar"], false)
    @subject.aggregate_timing("sampled_timing", 100, ["foo:bar"], false, :d, 0.01)

    finalizer = StatsD::Instrument::Aggregator.finalize(
      @subject.instance_variable_get(:@finalizer),
    )
    finalizer.call

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

  def test_aggregator_finalizer_is_called_on_gc
    skip_on_jruby("JRuby's GC does not guarantee finalizers are called promptly")

    5.times { @subject.increment("foo", 1, ["foo:bar"], false, 1.0) }

    @subject.instance_variable_get(:@flush_thread)&.kill
    @subject = nil

    assert_empty(@sink.datagrams)

    5.times do
      GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
      break if @sink.datagrams.any?

      sleep(0.1)
    end

    counter_datagram = @sink.datagrams.first
    assert_equal("foo", counter_datagram.name)
    assert_equal(5, counter_datagram.value)
    assert_equal(["foo:bar"], counter_datagram.tags)
  end

  def test_aggregator_finalizer_is_called_on_gc_after_aggregation_state_move
    (StatsD::Instrument::Aggregator::DEFAULT_MAX_CONTEXT_SIZE + 5).times do
      @subject.aggregate_timing("foo", 1, [], false, :d, 1.0)
    end
    assert_equal(1, @sink.datagrams.size)

    @subject = nil
    5.times do
      GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
      break if @sink.datagrams.size == 2

      sleep(0.1)
    end

    assert_equal(2, @sink.datagrams.size)
    counter_datagram = @sink.datagrams.last

    assert_equal("foo", counter_datagram.name)
    assert_equal([1, 1, 1, 1, 1], counter_datagram.value)
  end

  def test_signal_trap_context_fallback_to_direct_writes
    skip("#{RUBY_ENGINE} not supported for this test. Reason: signal handling") if RUBY_ENGINE != "ruby"

    signal_received = false
    metrics_sent_in_trap = []

    old_trap = Signal.trap("USR1") do
      signal_received = true
      @subject.increment("trap_counter", 1, [], false, 1.0)
      @subject.gauge("trap_gauge", 42, [], false)
      @subject.aggregate_timing("trap_timing", 100, [], false, :d, 1.0)

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

  private

  def unsorted_aggregator
    StatsD::Instrument::Aggregator.new(@sink, StatsD::Instrument::DatagramBuilder, nil, [], sort_tags: false)
  end
end
