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

  def test_legacy_client_is_default_client
    env = StatsD::Instrument::Environment.new({})
    assert_kind_of StatsD::Instrument::LegacyClient, env.client
  end

  def test_client_returns_new_client_if_envcironment_asks_for_it
    env = StatsD::Instrument::Environment.new('STATSD_USE_NEW_CLIENT' => '1')
    assert_kind_of StatsD::Instrument::Client, env.client
  end

  def test_client_from_env_uses_log_sink_in_development_environment
    env = StatsD::Instrument::Environment.new('STATSD_USE_NEW_CLIENT' => '1', 'STATSD_ENV' => 'development')
    assert_kind_of StatsD::Instrument::LogSink, env.client.sink
  end

  def test_client_from_env_uses_null_sink_in_test_environment
    env = StatsD::Instrument::Environment.new('STATSD_USE_NEW_CLIENT' => '1', 'STATSD_ENV' => 'test')
    assert_kind_of StatsD::Instrument::NullSink, env.client.sink
  end

  def test_client_from_env_uses_udp_sink_in_staging_environment
    env = StatsD::Instrument::Environment.new('STATSD_USE_NEW_CLIENT' => '1', 'STATSD_ENV' => 'staging')
    assert_kind_of StatsD::Instrument::UDPSink, env.client.sink
  end

  def test_client_from_env_uses_udp_sink_in_production_environment
    env = StatsD::Instrument::Environment.new('STATSD_USE_NEW_CLIENT' => '1', 'STATSD_ENV' => 'production')
    assert_kind_of StatsD::Instrument::UDPSink, env.client.sink
  end
end
