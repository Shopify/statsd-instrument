# frozen_string_literal: true

require "test_helper"

module Rails; end

class EnvironmentTest < Minitest::Test
  def test_environment_prefers_statsd_env_if_available
    env = StatsD::Instrument::Environment.new(
      "STATSD_ENV" => "set_from_STATSD_ENV",
      "RACK_ENV" => "set_from_RACK_ENV",
      "ENV" => "set_from_ENV",
    )
    assert_equal("set_from_STATSD_ENV", env.environment)
  end

  def test_environment_uses_env_when_rails_does_not_respond_to_env_and_statsd_env_is_not_set
    env = StatsD::Instrument::Environment.new(
      "ENV" => "set_from_ENV",
    )
    assert_equal("set_from_ENV", env.environment)
  end

  def test_environment_uses_rails_env_when_rails_is_available
    Rails.stubs(:env).returns("production")
    assert_equal("production", StatsD::Instrument::Environment.environment)
  end

  def test_environment_defaults_to_development
    env = StatsD::Instrument::Environment.new({})
    assert_equal("development", env.environment)
  end

  def test_client_returns_client_instance
    env = StatsD::Instrument::Environment.new({})
    assert_kind_of(StatsD::Instrument::Client, env.client)
  end

  def test_client_from_env_uses_log_sink_in_development_environment
    env = StatsD::Instrument::Environment.new("STATSD_USE_NEW_CLIENT" => "1", "STATSD_ENV" => "development")
    assert_kind_of(StatsD::Instrument::LogSink, env.client.sink)
  end

  def test_client_from_env_uses_null_sink_in_test_environment
    env = StatsD::Instrument::Environment.new("STATSD_USE_NEW_CLIENT" => "1", "STATSD_ENV" => "test")
    assert_kind_of(StatsD::Instrument::NullSink, env.client.sink)
  end

  def test_client_from_env_uses_batched_udp_sink_in_staging_environment
    env = StatsD::Instrument::Environment.new("STATSD_USE_NEW_CLIENT" => "1", "STATSD_ENV" => "staging")
    assert_kind_of(StatsD::Instrument::BatchedSink, env.client.sink)
  end

  def test_client_from_env_uses_batched_udp_sink_in_production_environment
    env = StatsD::Instrument::Environment.new("STATSD_USE_NEW_CLIENT" => "1", "STATSD_ENV" => "production")
    assert_kind_of(StatsD::Instrument::BatchedSink, env.client.sink)
  end

  def test_client_from_env_uses_regular_udp_sink_when_flush_interval_is_0
    StatsD::Instrument::Environment.any_instance.expects(:warn).with(
      "STATSD_FLUSH_INTERVAL=0.0 is deprecated, please set STATSD_BUFFER_CAPACITY=0 instead.",
    ).once
    env = StatsD::Instrument::Environment.new(
      "STATSD_USE_NEW_CLIENT" => "1",
      "STATSD_ENV" => "staging",
      "STATSD_FLUSH_INTERVAL" => "0.0",
    )
    assert_kind_of(StatsD::Instrument::Sink, env.client.sink)
  end

  def test_client_from_env_uses_regular_udp_sink_when_buffer_capacity_is_0
    env = StatsD::Instrument::Environment.new(
      "STATSD_USE_NEW_CLIENT" => "1",
      "STATSD_ENV" => "staging",
      "STATSD_BUFFER_CAPACITY" => "0",
    )
    assert_kind_of(StatsD::Instrument::Sink, env.client.sink)
  end
end
