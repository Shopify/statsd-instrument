require 'test_helper'

module ActiveMerchant; end
class ActiveMerchant::Base
  def ssl_post(arg)
    if arg
      'OK'
    else
      raise 'Not OK'
    end
  end

  def post_with_block(&block)
    yield if block_given?
  end
end

class ActiveMerchant::Gateway < ActiveMerchant::Base
  def purchase(arg)
    ssl_post(arg)
    true
  rescue
    false
  end

  def self.sync
    true
  end

  def self.singleton_class
    class << self; self; end
  end
end

class ActiveMerchant::UniqueGateway < ActiveMerchant::Base
  def ssl_post(arg)
    {:success => arg}
  end

  def purchase(arg)
    ssl_post(arg)
  end
end

class GatewaySubClass < ActiveMerchant::Gateway
end

ActiveMerchant::Base.extend StatsD::Instrument

class StatsDInstrumentationTest < Test::Unit::TestCase
  def test_statsd_count_if
    ActiveMerchant::Gateway.statsd_count_if :ssl_post, 'ActiveMerchant.Gateway.if'

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.if').once
    ActiveMerchant::Gateway.new.purchase(true)
    ActiveMerchant::Gateway.new.purchase(false)

    ActiveMerchant::Gateway.statsd_remove_count_if :ssl_post, 'ActiveMerchant.Gateway.if'
  end

  def test_statsd_count_if_with_method_receiving_block
    ActiveMerchant::Base.statsd_count_if :post_with_block, 'ActiveMerchant.Base.post_with_block' do |result|
      result == 'true'
    end

    StatsD.expects(:collect).with(:incr, 'ActiveMerchant.Base.post_with_block', 1, {}).once
    assert_equal 'true',  ActiveMerchant::Base.new.post_with_block { 'true' }
    assert_equal 'false', ActiveMerchant::Base.new.post_with_block { 'false' }

    ActiveMerchant::Base.statsd_remove_count_if :post_with_block, 'ActiveMerchant.Base.post_with_block'
  end

  def test_statsd_count_if_with_block
    ActiveMerchant::UniqueGateway.statsd_count_if :ssl_post, 'ActiveMerchant.Gateway.block' do |result|
      result[:success]
    end

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.block').once
    ActiveMerchant::UniqueGateway.new.purchase(true)
    ActiveMerchant::UniqueGateway.new.purchase(false)

    ActiveMerchant::UniqueGateway.statsd_remove_count_if :ssl_post, 'ActiveMerchant.Gateway.block'
  end

  def test_statsd_count_success
    ActiveMerchant::Gateway.statsd_count_success :ssl_post, 'ActiveMerchant.Gateway', 0.5

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.success', 1, 0.5).once
    StatsD.expects(:increment).with('ActiveMerchant.Gateway.failure', 1, 0.5).once

    ActiveMerchant::Gateway.new.purchase(true)
    ActiveMerchant::Gateway.new.purchase(false)

    ActiveMerchant::Gateway.statsd_remove_count_success :ssl_post, 'ActiveMerchant.Gateway'
  end

  def test_statsd_count_success_with_method_receiving_block
    ActiveMerchant::Base.statsd_count_success :post_with_block, 'ActiveMerchant.Base.post_with_block' do |result|
      result == 'successful'
    end

    StatsD.expects(:collect).with(:incr, 'ActiveMerchant.Base.post_with_block.success', 1, {}).once
    StatsD.expects(:collect).with(:incr, 'ActiveMerchant.Base.post_with_block.failure', 1, {}).once
    
    assert_equal 'successful', ActiveMerchant::Base.new.post_with_block { 'successful' }
    assert_equal 'not so successful', ActiveMerchant::Base.new.post_with_block { 'not so successful' }

    ActiveMerchant::Base.statsd_remove_count_success :post_with_block, 'ActiveMerchant.Base.post_with_block'
  end

  def test_statsd_count_success_with_block
    ActiveMerchant::UniqueGateway.statsd_count_success :ssl_post, 'ActiveMerchant.Gateway' do |result|
      result[:success]
    end

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.success', 1)
    ActiveMerchant::UniqueGateway.new.purchase(true)

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.failure', 1)
    ActiveMerchant::UniqueGateway.new.purchase(false)

    ActiveMerchant::UniqueGateway.statsd_remove_count_success :ssl_post, 'ActiveMerchant.Gateway'
  end

  def test_statsd_count
    ActiveMerchant::Gateway.statsd_count :ssl_post, 'ActiveMerchant.Gateway.ssl_post'

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.ssl_post', 1)
    ActiveMerchant::Gateway.new.purchase(true)

    ActiveMerchant::Gateway.statsd_remove_count :ssl_post, 'ActiveMerchant.Gateway.ssl_post'
  end

  def test_statsd_count_with_name_as_lambda
    metric_namer = lambda { |object, args| object.class.to_s.downcase + ".insert." + args.first.to_s }
    ActiveMerchant::Gateway.statsd_count(:ssl_post, metric_namer)

    StatsD.expects(:increment).with('gatewaysubclass.insert.true', 1)
    GatewaySubClass.new.purchase(true)

    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, metric_namer)
  end

  def test_statsd_count_with_method_receiving_block
    ActiveMerchant::Base.statsd_count :post_with_block, 'ActiveMerchant.Base.post_with_block'

    StatsD.expects(:collect).with(:incr, 'ActiveMerchant.Base.post_with_block', 1, {})
    assert_equal 'block called', ActiveMerchant::Base.new.post_with_block { 'block called' }

    ActiveMerchant::Base.statsd_remove_count :post_with_block, 'ActiveMerchant.Base.post_with_block'
  end

  def test_statsd_measure_with_nested_modules
    ActiveMerchant::UniqueGateway.statsd_measure :ssl_post, 'ActiveMerchant::Gateway.ssl_post'

    StatsD.expects(:measure).with('ActiveMerchant.Gateway.ssl_post', nil)
    ActiveMerchant::UniqueGateway.new.purchase(true)

    ActiveMerchant::UniqueGateway.statsd_remove_measure :ssl_post, 'ActiveMerchant::Gateway.ssl_post'
  end

  def test_statsd_measure
    ActiveMerchant::UniqueGateway.statsd_measure :ssl_post, 'ActiveMerchant.Gateway.ssl_post', 0.3

    StatsD.expects(:measure).with('ActiveMerchant.Gateway.ssl_post', nil, 0.3)
    ActiveMerchant::UniqueGateway.new.purchase(true)

    ActiveMerchant::UniqueGateway.statsd_remove_measure :ssl_post, 'ActiveMerchant.Gateway.ssl_post'
  end

  def test_statsd_measure_with_method_receiving_block
    ActiveMerchant::Base.statsd_measure :post_with_block, 'ActiveMerchant.Base.post_with_block'

    StatsD.expects(:collect).with(:ms, 'ActiveMerchant.Base.post_with_block', is_a(Float), {})
    assert_equal 'block called', ActiveMerchant::Base.new.post_with_block { 'block called' }

    ActiveMerchant::Base.statsd_remove_measure :post_with_block, 'ActiveMerchant.Base.post_with_block'
  end

  def test_instrumenting_class_method
    ActiveMerchant::Gateway.singleton_class.extend StatsD::Instrument
    ActiveMerchant::Gateway.singleton_class.statsd_count :sync, 'ActiveMerchant.Gateway.sync'

    StatsD.expects(:increment).with('ActiveMerchant.Gateway.sync', 1)
    ActiveMerchant::Gateway.sync

    ActiveMerchant::Gateway.singleton_class.statsd_remove_count :sync, 'ActiveMerchant.Gateway.sync'
  end
end
