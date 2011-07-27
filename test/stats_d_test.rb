require 'stats_d'
require 'test/unit'
require 'mocha'
require 'logger'

StatsD.logger = Logger.new('/dev/null')

module ActiveMerchant; end
class ActiveMerchant::Base
  def ssl_post(arg)
    if arg
      'OK'
    else
      raise 'Not OK'
    end
  end
end

class ActiveMerchant::Gateway < ActiveMerchant::Base
  def purchase(arg)
    ssl_post(arg)
    true
  rescue
    false
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

ActiveMerchant::Base.extend StatsD::Instrument

class StatsDTest < Test::Unit::TestCase
  def setup
    StatsD.stubs(:increment)
  end

  def test_statsd_count_if
    ActiveMerchant::Gateway.statsd_count_if :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}.if'

    StatsD.expects(:increment).with(includes('if')).once
    ActiveMerchant::Gateway.new.purchase(true)
    ActiveMerchant::Gateway.new.purchase(false)
  end

  def test_statsd_count_if_with_block
    ActiveMerchant::UniqueGateway.statsd_count_if :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}.block' do |result|
      result[:success]
    end

    StatsD.expects(:increment).with(includes('block')).once
    ActiveMerchant::UniqueGateway.new.purchase(true)
    ActiveMerchant::UniqueGateway.new.purchase(false)
  end

  def test_statsd_count_success
    ActiveMerchant::Gateway.statsd_count_success :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}'

    StatsD.expects(:increment).with(includes('success'))
    ActiveMerchant::Gateway.new.purchase(true)

    StatsD.expects(:increment).with(includes('failure'))
    ActiveMerchant::Gateway.new.purchase(false)
  end

  def test_statsd_count_success_with_block
    ActiveMerchant::UniqueGateway.statsd_count_success :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}' do |result|
      result[:success]
    end

    StatsD.expects(:increment).with(includes('success'))
    ActiveMerchant::UniqueGateway.new.purchase(true)

    StatsD.expects(:increment).with(includes('failure'))
    ActiveMerchant::UniqueGateway.new.purchase(false)
  end

  def test_statsd_count
    ActiveMerchant::Gateway.statsd_count :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}.ssl_post'

    StatsD.expects(:increment).with(includes('ssl_post'))
    ActiveMerchant::Gateway.new.purchase(true)
  end

  def test_statsd_measure
    ActiveMerchant::UniqueGateway.statsd_measure :ssl_post, 'ActiveMerchant.Billing.#{self.class.name}.ssl_post'

    StatsD.expects(:measure).with(includes('ssl_post')).returns({:success => true})
    ActiveMerchant::UniqueGateway.new.purchase(true)
  end

  def test_count_with_sampling
    StatsD.unstub(:increment)
    StatsD.stubs(:rand).returns(0.6)
    StatsD.logger.expects(:info).never

    StatsD.increment('sampling.foo.bar', 1, 0.1)
  end

  def test_count_with_successful_sample
    StatsD.unstub(:increment)
    StatsD.stubs(:rand).returns(0.01)
    StatsD.logger.expects(:info).once.with do |string|
      string.include?('@0.1')
    end

    StatsD.increment('sampling.foo.bar', 1, 0.1)
  end

  def test_production_mode_should_use_udp_socket
    StatsD.unstub(:increment)

    StatsD.mode = :production
    StatsD.server = 'localhost:123'
    UDPSocket.any_instance.expects(:send)

    StatsD.increment('fooz')
    StatsD.mode = :test
  end

  def test_should_not_write_when_disabled
    StatsD.enabled = false
    StatsD.expects(:logger).never
    StatsD.increment('fooz')
    StatsD.enabled = true
  end

  def test_receiving_TTOU_should_disable
    Process.kill("TTOU", $$)
    sleep 0.5
    assert !StatsD.enabled
  end

  def test_receiving_TTIN_should_disable
    StatsD.enabled = false

    Process.kill("TTIN", $$)
    sleep 0.5
    assert StatsD.enabled
  end
end
