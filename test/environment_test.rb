require 'test_helper'

class EnvironmentTest < Minitest::Test

  def setup
    ENV['STATSD_ADDR'] = nil
    ENV['IMPLEMENTATION'] = nil
  end

  def test_uses_logger_in_development_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('development')
    assert_instance_of StatsD::Instrument::Backends::LoggerBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_uses_mock_backend_in_test_environment
    StatsD::Instrument::Environment.stubs(:environment).returns('test')
    assert_instance_of StatsD::Instrument::Backends::MockBackend, StatsD::Instrument::Environment.default_backend
  end

  def test_uses_mock_backend_in_test_environment
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
end
