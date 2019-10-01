# frozen_string_literal: true

require 'test_helper'

require 'statsd/instrument/client'

class DogStatsDDatagramBuilderTest < Minitest::Test
  def setup
    @datagram_builder = StatsD::Instrument::DogStatsDDatagramBuilder.new
  end

  def test_raises_on_unsupported_metrics
    assert_raises(NotImplementedError) { @datagram_builder.kv('foo', 10, nil, nil) }
  end

  def test_service_check
    assert_equal '_sc|service|0', @datagram_builder._sc('service', :ok)
    datagram = @datagram_builder._sc('service', :warning, timestamp: Time.parse('2019-09-30T04:22:12Z'),
      hostname: 'localhost', tags: { foo: 'bar|baz' }, message: 'blah')
    assert_equal "_sc|service|1|h:localhost|d:1569817332|#foo:barbaz|m:blah", datagram
  end

  def test_event
    assert_equal '_e{5,5}:hello|world', @datagram_builder._e('hello', "world")

    datagram = @datagram_builder._e("testing", "with\nnewline", timestamp: Time.parse('2019-09-30T04:22:12Z'),
      hostname: 'localhost', aggregation_key: 'my-key', priority: 'low', source_type_name: 'source',
      alert_type: 'success', tags: { foo: 'bar|baz' })
    assert_equal '_e{7,13}:testing|with\\nnewline|h:localhost|d:1569817332|k:my-key|' \
      'p:low|s:source|t:success|#foo:barbaz', datagram
  end
end
