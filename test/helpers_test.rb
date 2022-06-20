# frozen_string_literal: true

require "test_helper"

class HelpersTest < Minitest::Test
  def setup
    test_class = Class.new(Minitest::Test)
    test_class.send(:include, StatsD::Instrument::Helpers)
    @test_case = test_class.new("fake")
  end

  def test_capture_metrics_inside_block_only
    StatsD.increment("counter")
    metrics = @test_case.capture_statsd_calls do
      StatsD.increment("counter")
      StatsD.gauge("gauge", 12)
    end
    StatsD.gauge("gauge", 15)

    assert_equal(2, metrics.length)
    assert_equal("counter", metrics[0].name)
    assert_equal("gauge", metrics[1].name)
    assert_equal(12, metrics[1].value)
  end

  def test_capture_metrics_with_new_client
    @old_client = StatsD.singleton_client
    StatsD.singleton_client = StatsD::Instrument::Client.new

    StatsD.increment("counter")
    metrics = @test_case.capture_statsd_datagrams do
      StatsD.increment("counter")
      StatsD.gauge("gauge", 12)
    end
    StatsD.gauge("gauge", 15)

    assert_equal(2, metrics.length)
  ensure
    StatsD.singleton_client = @old_client
  end

  def test_add_tag_works_for_nil
    assert_equal({ key: 123 }, StatsD::Instrument::Helpers.add_tag(nil, :key, 123))
  end

  def test_add_tag_works_for_hashes
    assert_equal({ key: 123 }, StatsD::Instrument::Helpers.add_tag({}, :key, 123))

    existing = { existing: 123 }
    assert_equal({ existing: 123, new: 456 }, StatsD::Instrument::Helpers.add_tag(existing, :new, 456))

    # ensure we do not modify the existing tags
    assert_equal({ existing: 123 }, existing)
  end

  def test_add_tag_works_for_arrays
    assert_equal(["key:123"], StatsD::Instrument::Helpers.add_tag([], :key, 123))

    existing = ["existing:123"]
    assert_equal(["existing:123", "new:456"], StatsD::Instrument::Helpers.add_tag(existing, :new, 456))

    # ensure we do not modify the existing tags
    assert_equal(["existing:123"], existing)
  end

  def test_add_tag_works_for_strings
    assert_equal("key:123", StatsD::Instrument::Helpers.add_tag("", :key, 123))

    existing = "existing:123"
    assert_equal("existing:123,new:456", StatsD::Instrument::Helpers.add_tag(existing, :new, 456))

    # ensure we do not modify the existing tags
    assert_equal("existing:123", existing)
  end

  def test_add_tags_raises_for_other
    assert_raises(ArgumentError, "add_tag only supports string, array or hash, Integer provided") do
      StatsD::Instrument::Helpers.add_tag(1, :key, 123)
    end
  end
end
