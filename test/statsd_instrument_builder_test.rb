# frozen_string_literal: true

require 'test_helper'

class StatsDInstrumentBuilderTest < Minitest::Test
  module ActiveMerchant
    class Base
      def ssl_post(arg)
        if arg
          'OK'
        else
          raise 'Not OK'
        end
      end

      def post_with_block(&block)
        block.call if block_given?
      end
    end

    class Gateway < Base
      def purchase(arg)
        ssl_post(arg)
        true
      rescue
        false
      end

      def self.sync
        true
      end
    end

    class UniqueGateway < Base
      def ssl_post(arg)
        { success: arg }
      end

      def purchase(arg)
        ssl_post(arg)
      end
    end
  end

  class GatewaySubClass < ActiveMerchant::Gateway
    def metric_name
      'subgateway'
    end
  end

  include StatsD::Instrument::Assertions

  def test_statsd_count_if
    StatsD.instrument(ActiveMerchant::Gateway) do |klass|
      klass.count_if(:ssl_post, 'ActiveMerchant.Gateway.if')
    end

    assert_statsd_increment('ActiveMerchant.Gateway.if') do
      ActiveMerchant::Gateway.new.purchase(true)
      ActiveMerchant::Gateway.new.purchase(false)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count_if(:ssl_post, 'ActiveMerchant.Gateway.if')
  end

  def test_statsd_count_success
    StatsD.instrument(ActiveMerchant::Gateway) do |klass|
      klass.count_success(:ssl_post, 'ActiveMerchant.Gateway', sample_rate: 0.5)
    end

    assert_statsd_increment('ActiveMerchant.Gateway.success', sample_rate: 0.5, times: 1) do
      ActiveMerchant::Gateway.new.purchase(true)
      ActiveMerchant::Gateway.new.purchase(false)
    end

    assert_statsd_increment('ActiveMerchant.Gateway.failure', sample_rate: 0.5, times: 1) do
      ActiveMerchant::Gateway.new.purchase(false)
      ActiveMerchant::Gateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count_success(:ssl_post, 'ActiveMerchant.Gateway')
  end

  def test_statsd_count
    StatsD.instrument(ActiveMerchant::Gateway) do |klass|
      klass.count(:ssl_post, 'ActiveMerchant.Gateway.ssl_post')
    end

    assert_statsd_increment('ActiveMerchant.Gateway.ssl_post') do
      ActiveMerchant::Gateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, 'ActiveMerchant.Gateway.ssl_post')
  end

  def test_statsd_measure
    StatsD.instrument(ActiveMerchant::UniqueGateway) do |klass|
      klass.measure(:ssl_post, 'ActiveMerchant.Gateway.ssl_post', sample_rate: 0.3)
    end

    assert_statsd_measure('ActiveMerchant.Gateway.ssl_post', sample_rate: 0.3) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_measure(:ssl_post, 'ActiveMerchant.Gateway.ssl_post')
  end

  def test_statsd_distribution
    StatsD.instrument(ActiveMerchant::UniqueGateway) do |klass|
      klass.distribution(:ssl_post, 'ActiveMerchant.Gateway.ssl_post', sample_rate: 0.3)
    end

    assert_statsd_distribution('ActiveMerchant.Gateway.ssl_post', sample_rate: 0.3) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_distribution(:ssl_post, 'ActiveMerchant.Gateway.ssl_post')
  end

  def test_instrumenting_class_method
    StatsD.instrument(ActiveMerchant::Gateway) do |klass|
      klass.count(:sync, 'ActiveMerchant.Gateway.sync', class_method: true)
    end

    assert_statsd_increment('ActiveMerchant.Gateway.sync') do
      ActiveMerchant::Gateway.sync
    end
  ensure
    ActiveMerchant::Gateway.singleton_class.statsd_remove_count(:sync, 'ActiveMerchant.Gateway.sync')
  end

  private

  def assert_scope(klass, method, expected_scope)
    method_scope = if klass.private_method_defined?(method)
      :private
    elsif klass.protected_method_defined?(method)
      :protected
    else
      :public
    end

    assert_equal(method_scope, expected_scope, "Expected method to be #{expected_scope}")
  end
end
