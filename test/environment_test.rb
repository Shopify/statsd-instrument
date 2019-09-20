# frozen_string_literal: true

require 'test_helper'

module Rails; end

class EnvironmentTest < Minitest::Test

  def setup
    ENV['STATSD_ADDR'] = nil
    ENV['IMPLEMENTATION'] = nil
  end

  def test_uses_logger_in_development_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('development')
    assert_instance_of StatsD::Instrument::Backends::LoggerBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_uses_null_backend_in_test_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('test')
    assert_instance_of StatsD::Instrument::Backends::NullBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_uses_udp_backend_in_production_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('production')
    assert_instance_of StatsD::Instrument::Backends::UDPBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_uses_environment_variables_in_production_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('production')
    ENV['STATSD_ADDR'] = '127.0.0.1:1234'
    ENV['STATSD_IMPLEMENTATION'] = 'datadog'

    backend = StatsD::Instrument::Environment.default_backend
    assert_equal '127.0.0.1', backend.host
    assert_equal 1234, backend.port
    assert_equal :datadog, backend.implementation
  end

  def test_uses_env_when_rails_does_not_respond_to_env
    assert_equal ENV['ENV'], StatsD::Instrument::Environment.environment
  end

  def test_uses_rails_env_when_rails_is_available
    Rails.stubs(:env).returns('production')
    assert_equal 'production', StatsD::Instrument::Environment.environment
  end
end
