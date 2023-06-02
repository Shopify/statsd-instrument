# frozen_string_literal: true

require "test_helper"

class DogStatsDDatagramBuilderTest < Minitest::Test
  def setup
    @datagram_builder = StatsD::Instrument::DogStatsDDatagramBuilder.new
  end

  def test_raises_on_unsupported_metrics
    assert_raises(NotImplementedError) { @datagram_builder.kv("foo", 10, nil, nil) }
  end

  def test_simple_service_check
    datagram = @datagram_builder._sc("service", :ok)
    assert_equal("_sc|service|0", datagram)
    parsed_datagram = StatsD::Instrument::DogStatsDDatagramBuilder.datagram_class.new(datagram)
    assert_equal(:_sc, parsed_datagram.type)
    assert_equal("service", parsed_datagram.name)
    assert_equal(0, parsed_datagram.value)
  end

  def test_complex_service_check
    datagram = @datagram_builder._sc(
      "service",
      :warning,
      timestamp: Time.parse("2019-09-30T04:22:12Z"),
      hostname: "localhost",
      tags: { foo: "bar|baz" },
      message: "blah",
    )
    assert_equal("_sc|service|1|h:localhost|d:1569817332|#foo:barbaz|m:blah", datagram)

    parsed_datagram = StatsD::Instrument::DogStatsDDatagramBuilder.datagram_class.new(datagram)
    assert_equal(:_sc, parsed_datagram.type)
    assert_equal("service", parsed_datagram.name)
    assert_equal(1, parsed_datagram.value)
    assert_equal("localhost", parsed_datagram.hostname)
    assert_equal(Time.parse("2019-09-30T04:22:12Z"), parsed_datagram.timestamp)
    assert_equal(["foo:barbaz"], parsed_datagram.tags)
    assert_equal("blah", parsed_datagram.message)
  end

  def test_simple_event
    datagram = @datagram_builder._e("hello", "world")
    assert_equal("_e{5,5}:hello|world", datagram)

    parsed_datagram = StatsD::Instrument::DogStatsDDatagramBuilder.datagram_class.new(datagram)
    assert_equal(:_e, parsed_datagram.type)
    assert_equal("hello", parsed_datagram.name)
    assert_equal("world", parsed_datagram.value)
  end

  def test_complex_event
    datagram = @datagram_builder._e(
      "testing",
      "with\nnewline",
      timestamp: Time.parse("2019-09-30T04:22:12Z"),
      hostname: "localhost",
      aggregation_key: "my-key",
      priority: "low",
      source_type_name: "source",
      alert_type: "success",
      tags: { foo: "bar|baz" },
    )
    assert_equal(
      '_e{7,13}:testing|with\\nnewline|h:localhost|d:1569817332|k:my-key|' \
        "p:low|s:source|t:success|#foo:barbaz",
      datagram,
    )

    parsed_datagram = StatsD::Instrument::DogStatsDDatagramBuilder.datagram_class.new(datagram)
    assert_equal(:_e, parsed_datagram.type)
    assert_equal("testing", parsed_datagram.name)
    assert_equal("with\nnewline", parsed_datagram.value)
    assert_equal("localhost", parsed_datagram.hostname)
    assert_equal(Time.parse("2019-09-30T04:22:12Z"), parsed_datagram.timestamp)
    assert_equal(["foo:barbaz"], parsed_datagram.tags)
    assert_equal("my-key", parsed_datagram.aggregation_key)
    assert_equal("low", parsed_datagram.priority)
    assert_equal("source", parsed_datagram.source_type_name)
    assert_equal("success", parsed_datagram.alert_type)
  end
end
