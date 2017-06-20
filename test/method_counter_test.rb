require 'test_helper'

class MethodCounterTest < Minitest::Test
  include StatsD::Instrument::Assertions

  class ToBeInstrumented
    def to_be_counted
      :return_value
    end

    def inspect
      '#<MethodCounterTest::ToBeInstrumented:instance>'
    end

    def self.to_be_counted_too
      :return_value
    end
  end

  ToBeInstrumented.prepend StatsD::Instrument.count_method(:to_be_counted)
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:to_be_counted_too)

  def test_instrumented_method_increments_statsd_counter_when_called
    assert_statsd_increment('to_be_counted') do
      return_value = ToBeInstrumented.new.to_be_counted
      assert_equal :return_value, return_value
    end
  end

  def test_instrumented_class_method_increments_statsd_counter_when_called
    assert_statsd_increment('to_be_counted_too') do
      return_value = ToBeInstrumented.to_be_counted_too
      assert_equal :return_value, return_value
    end
  end

  def test_instance_method_ancestors
    counter_module = ToBeInstrumented.ancestors.first
    assert_instance_of StatsD::Instrument::MethodCounter, counter_module
    assert_equal :to_be_counted, counter_module.method_name
    assert_equal '#<StatsD::Instrument::MethodCounter[:to_be_counted]>', counter_module.inspect
  end

  def test_singleton_class_method_ancestors
    counter_module = ToBeInstrumented.singleton_class.ancestors.first
    assert_instance_of StatsD::Instrument::MethodCounter, counter_module
    assert_equal :to_be_counted_too, counter_module.method_name
    assert_equal '#<StatsD::Instrument::MethodCounter[:to_be_counted_too]>', counter_module.inspect
  end

  def test_no_littering_in_instrumented_class
    refute_includes ToBeInstrumented.new.methods, :count_method
    refute_includes ToBeInstrumented.new.methods, :method_name
    refute_includes ToBeInstrumented.methods, :count_method
    refute_includes ToBeInstrumented.methods, :method_name

    assert_equal '#<MethodCounterTest::ToBeInstrumented:instance>', ToBeInstrumented.new.inspect
    assert_equal 'MethodCounterTest::ToBeInstrumented', ToBeInstrumented.inspect
  end
end
