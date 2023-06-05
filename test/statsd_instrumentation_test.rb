# frozen_string_literal: true

require "test_helper"

class StatsDInstrumentationTest < Minitest::Test
  module ActiveMerchant
    class Base
      extend StatsD::Instrument

      def ssl_post(arg, async: false)
        if arg
          "OK"
        else
          raise "Not OK"
        end
      end

      def post_with_block(&block)
        block.call if block_given?
      end
    end

    class Gateway < Base
      def purchase(arg, async: false)
        ssl_post(arg, async: async)
        true
      rescue
        false
      end

      class << self
        def sync
          true
        end
      end
    end

    class UniqueGateway < Base
      def ssl_post(arg, async: false)
        { success: arg }
      end

      def purchase(arg, async: false)
        ssl_post(arg, async: async)
      end
    end
  end

  class GatewaySubClass < ActiveMerchant::Gateway
    def metric_name
      "subgateway"
    end
  end

  class InstrumentedClass
    extend StatsD::Instrument

    def public_and_instrumented
    end
    statsd_count :public_and_instrumented, "InstrumentedClass.public_and_instrumented"

    protected

    def protected_and_instrumented
    end
    statsd_count :protected_and_instrumented, "InstrumentedClass.protected_and_instrumented"

    private

    def private_and_instrumented
    end
    statsd_count :private_and_instrumented, "InstrumentedClass.private_and_instrumented"
  end

  include StatsD::Instrument::Assertions

  def test_statsd_count_if
    ActiveMerchant::Gateway.statsd_count_if(:ssl_post, "ActiveMerchant.Gateway.if")

    assert_statsd_increment("ActiveMerchant.Gateway.if") do
      ActiveMerchant::Gateway.new.purchase(true)
      ActiveMerchant::Gateway.new.purchase(false)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count_if(:ssl_post, "ActiveMerchant.Gateway.if")
  end

  def test_statsd_count_if_with_method_receiving_block
    ActiveMerchant::Base.statsd_count_if(:post_with_block, "ActiveMerchant.Base.post_with_block") do |result|
      result == "true"
    end

    assert_statsd_increment("ActiveMerchant.Base.post_with_block") do
      assert_equal("true", ActiveMerchant::Base.new.post_with_block { "true" })
      assert_equal("false", ActiveMerchant::Base.new.post_with_block { "false" })
    end
  ensure
    ActiveMerchant::Base.statsd_remove_count_if(:post_with_block, "ActiveMerchant.Base.post_with_block")
  end

  def test_statsd_count_if_with_block
    ActiveMerchant::UniqueGateway.statsd_count_if(:ssl_post, "ActiveMerchant.Gateway.block") do |result|
      result[:success]
    end

    assert_statsd_increment("ActiveMerchant.Gateway.block", times: 1) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
      ActiveMerchant::UniqueGateway.new.purchase(false)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_count_if(:ssl_post, "ActiveMerchant.Gateway.block")
  end

  def test_statsd_count_success
    ActiveMerchant::Gateway.statsd_count_success(:ssl_post, "ActiveMerchant.Gateway", sample_rate: 0.5)

    assert_statsd_increment("ActiveMerchant.Gateway.success", sample_rate: 0.5, times: 1) do
      ActiveMerchant::Gateway.new.purchase(true)
      ActiveMerchant::Gateway.new.purchase(false)
    end

    assert_statsd_increment("ActiveMerchant.Gateway.failure", sample_rate: 0.5, times: 1) do
      ActiveMerchant::Gateway.new.purchase(false)
      ActiveMerchant::Gateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count_success(:ssl_post, "ActiveMerchant.Gateway")
  end

  def test_statsd_count_success_with_method_receiving_block
    ActiveMerchant::Base.statsd_count_success(:post_with_block, "ActiveMerchant.Base.post_with_block") do |result|
      result == "successful"
    end

    assert_statsd_increment("ActiveMerchant.Base.post_with_block.success", times: 1) do
      assert_equal("successful", ActiveMerchant::Base.new.post_with_block { "successful" })
      assert_equal("not so successful", ActiveMerchant::Base.new.post_with_block { "not so successful" })
    end

    assert_statsd_increment("ActiveMerchant.Base.post_with_block.failure", times: 1) do
      assert_equal("successful", ActiveMerchant::Base.new.post_with_block { "successful" })
      assert_equal("not so successful", ActiveMerchant::Base.new.post_with_block { "not so successful" })
    end
  ensure
    ActiveMerchant::Base.statsd_remove_count_success(:post_with_block, "ActiveMerchant.Base.post_with_block")
  end

  def test_statsd_count_success_with_block
    ActiveMerchant::UniqueGateway.statsd_count_success(:ssl_post, "ActiveMerchant.Gateway") do |result|
      result[:success]
    end

    assert_statsd_increment("ActiveMerchant.Gateway.success") do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end

    assert_statsd_increment("ActiveMerchant.Gateway.failure") do
      ActiveMerchant::UniqueGateway.new.purchase(false)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_count_success(:ssl_post, "ActiveMerchant.Gateway")
  end

  def test_statsd_count_success_tag_error_class
    ActiveMerchant::Base.statsd_count_success(:ssl_post, "ActiveMerchant.Base", tag_error_class: true)

    assert_statsd_increment("ActiveMerchant.Base.success", tags: nil) do
      ActiveMerchant::Base.new.ssl_post(true)
    end

    assert_statsd_increment("ActiveMerchant.Base.failure", tags: ["error_class:RuntimeError"]) do
      assert_raises(RuntimeError, "Not OK") do
        ActiveMerchant::Base.new.ssl_post(false)
      end
    end
  ensure
    ActiveMerchant::Base.statsd_remove_count_success(:ssl_post, "ActiveMerchant.Base")
  end

  def test_statsd_count_success_tag_error_class_is_opt_in
    ActiveMerchant::Base.statsd_count_success(:ssl_post, "ActiveMerchant.Base")

    assert_statsd_increment("ActiveMerchant.Base.success", tags: nil) do
      ActiveMerchant::Base.new.ssl_post(true)
    end

    assert_statsd_increment("ActiveMerchant.Base.failure", tags: nil) do
      assert_raises(RuntimeError, "Not OK") do
        ActiveMerchant::Base.new.ssl_post(false)
      end
    end
  ensure
    ActiveMerchant::Base.statsd_remove_count_success(:ssl_post, "ActiveMerchant.Base")
  end

  def test_statsd_count
    ActiveMerchant::Gateway.statsd_count(:ssl_post, "ActiveMerchant.Gateway.ssl_post")

    assert_statsd_increment("ActiveMerchant.Gateway.ssl_post") do
      ActiveMerchant::Gateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_count_with_name_as_lambda
    metric_namer = lambda { |object, args| "#{object.metric_name}.#{args.first}" }
    ActiveMerchant::Gateway.statsd_count(:ssl_post, metric_namer)

    assert_statsd_increment("subgateway.foo") do
      GatewaySubClass.new.purchase("foo")
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, metric_namer)
  end

  def test_statsd_count_with_name_as_proc
    metric_namer = proc { |object, args| "#{object.metric_name}.#{args.first}" }
    ActiveMerchant::Gateway.statsd_count(:ssl_post, metric_namer)

    assert_statsd_increment("subgateway.foo") do
      GatewaySubClass.new.purchase("foo")
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, metric_namer)
  end

  def test_statsd_count_with_tags_as_lambda
    metric_namer = lambda { |object, args| "#{object.metric_name}.#{args.first}" }
    metric_tagger = lambda { |_object, args| { "key": args.first } }
    ActiveMerchant::Gateway.statsd_count(:ssl_post, metric_namer, tags: metric_tagger)

    assert_statsd_increment("subgateway.foo", tags: { "key": "foo" }) do
      GatewaySubClass.new.purchase("foo")
    end
    assert_statsd_increment("subgateway.bar", tags: { "key": "bar" }) do
      GatewaySubClass.new.purchase("bar")
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, metric_namer)
  end

  def test_statsd_count_with_tags_as_proc
    metric_namer = proc { |object, args| "#{object.metric_name}.#{args.first}" }
    metric_tagger = proc { |_object, args| { "key": args.first } }
    ActiveMerchant::Gateway.statsd_count(:ssl_post, metric_namer, tags: metric_tagger)

    assert_statsd_increment("subgateway.foo", tags: { "key": "foo" }) do
      GatewaySubClass.new.purchase("foo")
    end
    assert_statsd_increment("subgateway.bar", tags: { "key": "bar" }) do
      GatewaySubClass.new.purchase("bar")
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, metric_namer)
  end

  def test_statsd_count_with_method_receiving_block
    ActiveMerchant::Base.statsd_count(:post_with_block, "ActiveMerchant.Base.post_with_block")

    assert_statsd_increment("ActiveMerchant.Base.post_with_block") do
      assert_equal("block called", ActiveMerchant::Base.new.post_with_block { "block called" })
    end
  ensure
    ActiveMerchant::Base.statsd_remove_count(:post_with_block, "ActiveMerchant.Base.post_with_block")
  end

  def test_statsd_measure
    ActiveMerchant::UniqueGateway.statsd_measure(:ssl_post, "ActiveMerchant.Gateway.ssl_post", sample_rate: 0.3)

    assert_statsd_measure("ActiveMerchant.Gateway.ssl_post", sample_rate: 0.3) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_measure(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_measure_uses_normalized_metric_name
    ActiveMerchant::UniqueGateway.statsd_measure(:ssl_post, "ActiveMerchant::Gateway.ssl_post")

    assert_statsd_measure("ActiveMerchant.Gateway.ssl_post") do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_measure(:ssl_post, "ActiveMerchant::Gateway.ssl_post")
  end

  def test_statsd_measure_raises_without_a_provided_block
    assert_raises(LocalJumpError) do
      assert_statsd_measure("ActiveMerchant.Gateway.ssl_post")
    end
  end

  def test_statsd_measure_with_method_receiving_block
    ActiveMerchant::Base.statsd_measure(:post_with_block, "ActiveMerchant.Base.post_with_block")

    assert_statsd_measure("ActiveMerchant.Base.post_with_block") do
      assert_equal("block called", ActiveMerchant::Base.new.post_with_block { "block called" })
    end
  ensure
    ActiveMerchant::Base.statsd_remove_measure(:post_with_block, "ActiveMerchant.Base.post_with_block")
  end

  def test_statsd_measure_with_sample_rate
    ActiveMerchant::UniqueGateway.statsd_measure(:ssl_post, "ActiveMerchant.Gateway.ssl_post", sample_rate: 0.1)

    assert_statsd_measure("ActiveMerchant.Gateway.ssl_post", sample_rate: 0.1) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_measure(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_distribution
    ActiveMerchant::UniqueGateway.statsd_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post", sample_rate: 0.3)

    assert_statsd_distribution("ActiveMerchant.Gateway.ssl_post", sample_rate: 0.3) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_distribution_uses_normalized_metric_name
    ActiveMerchant::UniqueGateway.statsd_distribution(:ssl_post, "ActiveMerchant::Gateway.ssl_post")

    assert_statsd_distribution("ActiveMerchant.Gateway.ssl_post") do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_distribution(:ssl_post, "ActiveMerchant::Gateway.ssl_post")
  end

  def test_statsd_distribution_raises_without_a_provided_block
    assert_raises(LocalJumpError) do
      assert_statsd_distribution("ActiveMerchant.Gateway.ssl_post")
    end
  end

  def test_statsd_distribution_with_method_receiving_block
    ActiveMerchant::Base.statsd_distribution(:post_with_block, "ActiveMerchant.Base.post_with_block")

    assert_statsd_distribution("ActiveMerchant.Base.post_with_block") do
      assert_equal("block called", ActiveMerchant::Base.new.post_with_block { "block called" })
    end
  ensure
    ActiveMerchant::Base.statsd_remove_distribution(:post_with_block, "ActiveMerchant.Base.post_with_block")
  end

  def test_statsd_distribution_with_tags
    ActiveMerchant::UniqueGateway.statsd_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post", tags: ["foo"])

    assert_statsd_distribution("ActiveMerchant.Gateway.ssl_post", tags: ["foo"]) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_distribution_with_sample_rate
    ActiveMerchant::UniqueGateway.statsd_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post", sample_rate: 0.1)

    assert_statsd_distribution("ActiveMerchant.Gateway.ssl_post", sample_rate: 0.1) do
      ActiveMerchant::UniqueGateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::UniqueGateway.statsd_remove_distribution(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_instrumenting_class_method
    ActiveMerchant::Gateway.singleton_class.extend(StatsD::Instrument)
    ActiveMerchant::Gateway.singleton_class.statsd_count(:sync, "ActiveMerchant.Gateway.sync")

    assert_statsd_increment("ActiveMerchant.Gateway.sync") do
      ActiveMerchant::Gateway.sync
    end
  ensure
    ActiveMerchant::Gateway.singleton_class.statsd_remove_count(:sync, "ActiveMerchant.Gateway.sync")
  end

  def test_statsd_count_with_tags
    ActiveMerchant::Gateway.singleton_class.extend(StatsD::Instrument)
    ActiveMerchant::Gateway.singleton_class.statsd_count(:sync, "ActiveMerchant.Gateway.sync", tags: { key: "value" })

    assert_statsd_increment("ActiveMerchant.Gateway.sync", tags: ["key:value"]) do
      ActiveMerchant::Gateway.sync
    end
  ensure
    ActiveMerchant::Gateway.singleton_class.statsd_remove_count(:sync, "ActiveMerchant.Gateway.sync")
  end

  def test_statsd_respects_global_prefix_changes
    old_client = StatsD.singleton_client

    StatsD.singleton_client = StatsD::Instrument::Client.new(prefix: "Foo")
    ActiveMerchant::Gateway.singleton_class.extend(StatsD::Instrument)
    ActiveMerchant::Gateway.singleton_class.statsd_count(:sync, "ActiveMerchant.Gateway.sync")
    StatsD.singleton_client = StatsD::Instrument::Client.new(prefix: "Quc")

    datagrams = capture_statsd_calls { ActiveMerchant::Gateway.sync }
    assert_equal(1, datagrams.length)
    assert_equal("Quc.ActiveMerchant.Gateway.sync", datagrams.first.name)
  ensure
    StatsD.singleton_client = old_client
    ActiveMerchant::Gateway.singleton_class.statsd_remove_count(:sync, "ActiveMerchant.Gateway.sync")
  end

  def test_statsd_count_with_injected_client
    client = StatsD::Instrument::Client.new(prefix: "prefix")

    ActiveMerchant::Gateway.statsd_count(:ssl_post, "ActiveMerchant.Gateway.ssl_post", client: client)
    assert_statsd_increment("ActiveMerchant.Gateway.ssl_post", client: client) do
      ActiveMerchant::Gateway.new.purchase(true)
    end
  ensure
    ActiveMerchant::Gateway.statsd_remove_count(:ssl_post, "ActiveMerchant.Gateway.ssl_post")
  end

  def test_statsd_macro_can_disable_prefix
    client = StatsD::Instrument::Client.new(prefix: "foo")
    ActiveMerchant::Gateway.singleton_class.extend(StatsD::Instrument)
    ActiveMerchant::Gateway.singleton_class.statsd_count_success(
      :sync,
      "ActiveMerchant.Gateway.sync",
      no_prefix: true,
      client: client,
    )

    datagrams = client.capture { ActiveMerchant::Gateway.sync }
    assert_equal(1, datagrams.length)
    assert_equal("ActiveMerchant.Gateway.sync.success", datagrams.first.name)
  ensure
    ActiveMerchant::Gateway.singleton_class.statsd_remove_count_success(:sync, "ActiveMerchant.Gateway.sync")
  end

  def test_statsd_doesnt_change_method_scope_of_public_method
    assert_scope(InstrumentedClass, :public_and_instrumented, :public)

    assert_statsd_increment("InstrumentedClass.public_and_instrumented") do
      InstrumentedClass.new.send(:public_and_instrumented)
    end
  end

  def test_statsd_doesnt_change_method_scope_of_protected_method
    assert_scope(InstrumentedClass, :protected_and_instrumented, :protected)

    assert_statsd_increment("InstrumentedClass.protected_and_instrumented") do
      InstrumentedClass.new.send(:protected_and_instrumented)
    end
  end

  def test_statsd_doesnt_change_method_scope_of_private_method
    assert_scope(InstrumentedClass, :private_and_instrumented, :private)

    assert_statsd_increment("InstrumentedClass.private_and_instrumented") do
      InstrumentedClass.new.send(:private_and_instrumented)
    end
  end

  def test_statsd_doesnt_change_method_scope_on_removal_of_public_method
    assert_scope(InstrumentedClass, :public_and_instrumented, :public)
    InstrumentedClass.statsd_remove_count(:public_and_instrumented, "InstrumentedClass.public_and_instrumented")
    assert_scope(InstrumentedClass, :public_and_instrumented, :public)

    InstrumentedClass.statsd_count(:public_and_instrumented, "InstrumentedClass.public_and_instrumented")
  end

  def test_statsd_doesnt_change_method_scope_on_removal_of_protected_method
    assert_scope(InstrumentedClass, :protected_and_instrumented, :protected)
    InstrumentedClass.statsd_remove_count(:protected_and_instrumented, "InstrumentedClass.protected_and_instrumented")
    assert_scope(InstrumentedClass, :protected_and_instrumented, :protected)

    InstrumentedClass.statsd_count(:protected_and_instrumented, "InstrumentedClass.protected_and_instrumented")
  end

  def test_statsd_doesnt_change_method_scope_on_removal_of_private_method
    assert_scope(InstrumentedClass, :private_and_instrumented, :private)
    InstrumentedClass.statsd_remove_count(:private_and_instrumented, "InstrumentedClass.private_and_instrumented")
    assert_scope(InstrumentedClass, :private_and_instrumented, :private)

    InstrumentedClass.statsd_count(:private_and_instrumented, "InstrumentedClass.private_and_instrumented")
  end

  def test_statsd_works_with_prepended_modules
    mod = Module.new do
      define_method(:foo) { super() }
    end
    klass = Class.new do
      prepend mod
      extend StatsD::Instrument
      define_method(:foo) {}
      statsd_count :foo, "foo"
    end

    assert_statsd_increment("foo") do
      klass.new.foo
    end
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
