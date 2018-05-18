module StatsD::Instrument::Assertions
  include StatsD::Instrument::Helpers

  def assert_no_statsd_calls(metric_name = nil, &block)
    metrics = capture_statsd_calls(&block)
    metrics.select! { |m| m.name == metric_name } if metric_name
    assert metrics.empty?, "No StatsD calls for metric #{metrics.map(&:name).join(', ')} expected."
  end

  def assert_statsd_increment(metric_name, options = {}, &block)
    assert_statsd_call(:c, metric_name, options, &block)
  end

  def assert_statsd_measure(metric_name, options = {}, &block)
    assert_statsd_call(:ms, metric_name, options, &block)
  end

  def assert_statsd_gauge(metric_name, options = {}, &block)
    assert_statsd_call(:g, metric_name, options, &block)
  end

  def assert_statsd_histogram(metric_name, options = {}, &block)
    assert_statsd_call(:h, metric_name, options, &block)
  end

  def assert_statsd_distribution(metric_name, options = {}, &block)
    assert_statsd_call(:d, metric_name, options, &block)
  end

  def assert_statsd_set(metric_name, options = {}, &block)
    assert_statsd_call(:s, metric_name, options, &block)
  end

  def assert_statsd_key_value(metric_name, options = {}, &block)
    assert_statsd_call(:kv, metric_name, options, &block)
  end

  # @private
  def assert_statsd_calls(expected_metrics, &block)
    unless block
      raise ArgumentError, "block must be given"
    end

    metrics = capture_statsd_calls(&block)
    matched_expected_metrics = []

    expected_metrics.each do |expected_metric|
      expected_metric_times = expected_metric.times
      expected_metric_times_remaining = expected_metric.times
      filtered_metrics = metrics.select { |m| m.type == expected_metric.type && m.name == expected_metric.name }
      assert filtered_metrics.length > 0,
        "No StatsD calls for metric #{expected_metric.name} of type #{expected_metric.type} were made."

      filtered_metrics.each do |metric|
        assert within_numeric_range?(metric.sample_rate),
          "Unexpected sample rate type for metric #{metric.name}, must be numeric"
        if expected_metric.matches(metric)
          assert expected_metric_times_remaining > 0,
            "Unexpected StatsD call; number of times this metric was expected exceeded: #{expected_metric.inspect}"
          expected_metric_times_remaining -= 1
          metrics.delete(metric)
          if expected_metric_times_remaining == 0
            matched_expected_metrics << expected_metric
          end
        end
      end

      assert expected_metric_times_remaining == 0,
          "Metric expected #{expected_metric_times} times but seen"\
          " #{expected_metric_times-expected_metric_times_remaining}"\
          " times: #{expected_metric.inspect}"
    end
    expected_metrics -= matched_expected_metrics

    assert expected_metrics.empty?,
      "Unexpected StatsD calls; the following metric expectations were not satisfied: #{expected_metrics.inspect}"
  end

  private

  def assert_statsd_call(metric_type, metric_name, options = {}, &block)
    options[:name] = metric_name
    options[:type] = metric_type
    options[:times] ||= 1
    expected_metric = StatsD::Instrument::MetricExpectation.new(options)
    assert_statsd_calls([expected_metric], &block)
  end

  def within_numeric_range?(object)
    object.kind_of?(Numeric) && (0.0..1.0).cover?(object)
  end
end
