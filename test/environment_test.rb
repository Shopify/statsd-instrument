# frozen_string_literal: true

require 'test_helper'

module Rails; end

class EnvironmentTest < Minitest::Test
  def setup
    ENV['STATSD_ADDR'] = nil
    ENV['IMPLEMENTATION'] = nil
  end

  def test_default_backend_uses_logger_in_development_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('development')
    assert_instance_of StatsD::Instrument::Backends::LoggerBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_default_backend_uses_null_backend_in_test_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('test')
    assert_instance_of StatsD::Instrument::Backends::NullBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_default_backend_uses_udp_backend_in_production_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('production')
    assert_instance_of StatsD::Instrument::Backends::UDPBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_default_backend_uses_environment_variables_in_production_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('production')
    ENV['STATSD_ADDR'] = '127.0.0.1:1234'
    ENV['STATSD_IMPLEMENTATION'] = 'datadog'

    backend = StatsD::Instrument::Environment.default_backend
    assert_equal '127.0.0.1', backend.host
    assert_equal 1234, backend.port
    assert_equal :datadog, backend.implementation
  end

  def test_environment_prefers_statsd_env_if_available
    env = StatsD::Instrument::Environment.new(
      'STATSD_ENV' => 'set_from_STATSD_ENV',
      'RACK_ENV' => 'set_from_RACK_ENV',
      'ENV' => 'set_from_ENV',
    )
    assert_equal 'set_from_STATSD_ENV', env.environment
  end

  def test_environment_uses_env_when_rails_does_not_respond_to_env_and_statsd_env_is_not_set
    env = StatsD::Instrument::Environment.new(
      'ENV' => 'set_from_ENV',
    )
    assert_equal 'set_from_ENV', env.environment
  end

  def test_environment_uses_rails_env_when_rails_is_available
    Rails.stubs(:env).returns('production')
    assert_equal 'production', StatsD::Instrument::Environment.environment
  end

  def test_environment_defaults_to_development
    env = StatsD::Instrument::Environment.new({})
    assert_equal 'development', env.environment
  end

  def test_default_client_uses_log_sink_in_development_environment
    env = StatsD::Instrument::Environment.new('STATSD_ENV' => 'development')
    assert_kind_of StatsD::Instrument::LogSink, env.default_client.sink
  end

  def test_default_client_uses_null_sink_in_test_environment
    env = StatsD::Instrument::Environment.new('STATSD_ENV' => 'test')
    assert_kind_of StatsD::Instrument::NullSink, env.default_client.sink
  end

  def test_default_client_uses_udp_sink_in_staging_environment
    env = StatsD::Instrument::Environment.new('STATSD_ENV' => 'staging')
    assert_kind_of StatsD::Instrument::UDPSink, env.default_client.sink
  end

  def test_default_client_uses_udp_sink_in_production_environment
    env = StatsD::Instrument::Environment.new('STATSD_ENV' => 'production')
    assert_kind_of StatsD::Instrument::UDPSink, env.default_client.sink
  end

  def test_default_client_respects_statsd_environment_variables
    env = StatsD::Instrument::Environment.new(
      'STATSD_ENV' => 'production',
      'STATSD_IMPLEMENTATION' => 'datadog',
      'STATSD_ADDR' => 'foo:8125',
      'STATSD_SAMPLE_RATE' => "0.1",
      'STATSD_PREFIX' => "foo",
      'STATSD_DEFAULT_TAGS' => "foo,bar:baz",
    )

    assert_equal StatsD::Instrument::DogStatsDDatagramBuilder, env.default_client.datagram_builder_class
    assert_equal 'foo', env.default_client.sink.host
    assert_equal 8125, env.default_client.sink.port
    assert_equal 0.1, env.default_client.default_sample_rate
    assert_equal "foo", env.default_client.prefix
    assert_equal ["foo", "bar:baz"], env.default_client.default_tags
  end

  def test_default_client_has_sensible_defaults
    env = StatsD::Instrument::Environment.new('STATSD_ENV' => 'production')

    assert_equal StatsD::Instrument::StatsDDatagramBuilder, env.default_client.datagram_builder_class
    assert_equal 'localhost', env.default_client.sink.host
    assert_equal 8125, env.default_client.sink.port
    assert_equal 1.0, env.default_client.default_sample_rate
    assert_nil env.default_client.prefix
    assert_nil env.default_client.default_tags
  end
end
