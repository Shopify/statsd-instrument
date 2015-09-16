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

  def assert_statsd_set(metric_name, options = {}, &block)
    assert_statsd_call(:s, metric_name, options, &block)
  end

  def assert_statsd_key_value(metric_name, options = {}, &block)
    assert_statsd_call(:kv, metric_name, options, &block)
  end

  private

  def assert_statsd_call(metric_type, metric_name, options = {}, &block)
    options[:times] ||= 1
    metrics = capture_statsd_calls(&block)
    metrics = metrics.select { |m| m.type == metric_type && m.name == metric_name }
    assert metrics.length > 0, "No StatsD calls for metric #{metric_name} were made."
    assert options[:times] === metrics.length, "The amount of StatsD calls for metric #{metric_name} was unexpected. Expected #{options[:times].inspect}, found #{metrics.length}"
    metric = metrics.first

    assert_equal options[:sample_rate], metric.sample_rate, "Unexpected value submitted for StatsD metric #{metric_name}" if options[:sample_rate]
    assert_equal options[:value], metric.value, "Unexpected StatsD sample rate for metric #{metric_name}" if options[:value]

    if options[:tags]
      expected_tags = Set.new(StatsD::Instrument::Metric.normalize_tags(options[:tags]))
      actual_tags = Set.new(metric.tags)

      if options[:ignore_tags]
        ignored_tags = Set.new(StatsD::Instrument::Metric.normalize_tags(options[:ignore_tags])) - expected_tags
        actual_tags -= ignored_tags

        if options[:ignore_tags].is_a?(Array)
          actual_tags.delete_if{ |key| options[:ignore_tags].include?(key.split(":").first) }
        end
      end

      assert_equal expected_tags, actual_tags,
        "Unexpected StatsD tags for metric #{metric_name}. Expected: #{expected_tags.inspect}, actual: #{actual_tags.inspect}"
    end

    metric
  end
end
