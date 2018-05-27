require 'test_helper'

class MethodCounterTest < Minitest::Test
  include StatsD::Instrument::Assertions

  class ToBeInstrumented
    class << self
      def to_be_counted_too
        :return_value
      end

      def to_raise_too
        raise "💥"
      end

      def to_raise_too_with_suffix
        raise StandardError.new("boom!")
      end

      def to_be_counted_too_with_suffix
        :return_value
      end

      protected

      def i_am_protected_too
        :return_value
      end

      private

      def i_am_private_too
        :return_value
      end
    end

    def to_be_counted
      :return_value
    end

    def to_be_counted_with_suffix
      :return_value
    end

    def to_raise
      raise "💥"
    end

    def to_raise_with_suffix
      raise StandardError.new("boom!")
    end

    def inspect
      '#<MethodCounterTest::ToBeInstrumented:instance>'
    end

    protected

    def i_am_protected
      :return_value
    end

    private

    def i_am_private
      :return_value
    end
  end

  SuffixedExcpetionHandler = -> (metric, ex) { metric.name = "#{metric.name}.#{ex.class}" }
  SuffixedHandler = -> (metric, result) { metric.name = "#{metric.name}.#{result}" }

  ToBeInstrumented.prepend StatsD::Instrument.count_method(:i_am_protected, name: "i_am_protected")
  ToBeInstrumented.prepend StatsD::Instrument.count_method(:i_am_private, name: "i_am_private")
  ToBeInstrumented.prepend StatsD::Instrument.count_method(:to_raise, name: "to_raise")
  ToBeInstrumented.prepend StatsD::Instrument.count_method(:to_raise_with_suffix, name: "to_raise_with_suffix", on_exception: SuffixedExcpetionHandler)
  ToBeInstrumented.prepend StatsD::Instrument.count_method(:to_be_counted_with_suffix, name: "to_be_counted_with_suffix", on_success: SuffixedHandler)
  ToBeInstrumented.prepend StatsD::Instrument.count_method(:to_be_counted, name: "to_be_counted")
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:i_am_protected, name: "i_am_protected_too")
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:i_am_private, name: "i_am_private_too")
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:to_raise_too, name: "to_raise_too")
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:to_raise_too_with_suffix, name: "to_raise_too_with_suffix", on_exception: SuffixedExcpetionHandler)
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:to_be_counted_too_with_suffix, name: "to_be_counted_too_with_suffix", on_success: SuffixedHandler)
  ToBeInstrumented.singleton_class.prepend StatsD::Instrument.count_method(:to_be_counted_too, name: "to_be_counted_too")

  def test_instrumented_method_increments_statsd_counter_when_called
    assert_statsd_increment('to_be_counted') do
      return_value = ToBeInstrumented.new.to_be_counted
      assert_equal :return_value, return_value
    end
  end

  def test_instrumented_method_increments_statsd_counter_when_called_and_appends_suffix
    assert_statsd_increment('to_be_counted_with_suffix.return_value') do
      return_value = ToBeInstrumented.new.to_be_counted_with_suffix
      assert_equal :return_value, return_value
    end
  end

  def test_instrumented_method_is_discarded_on_exceptions
    assert_no_statsd_calls do
      assert_raises do
        ToBeInstrumented.new.to_raise
      end
    end
  end

  def test_instrumented_method_add_suffix_on_exceptions
    assert_statsd_increment('to_raise_with_suffix.StandardError') do
      assert_raises do
        ToBeInstrumented.new.to_raise_with_suffix
      end
    end
  end

  def test_instrumented_class_method_increments_statsd_counter_when_called
    assert_statsd_increment('to_be_counted_too') do
      return_value = ToBeInstrumented.to_be_counted_too
      assert_equal :return_value, return_value
    end
  end

  def test_instrumented_class_method_increments_statsd_counter_when_called_and_appends_suffix
    assert_statsd_increment('to_be_counted_too_with_suffix.return_value') do
      return_value = ToBeInstrumented.to_be_counted_too_with_suffix
      assert_equal :return_value, return_value
    end
  end

  def test_instrumented_class_method_is_discarded_on_exceptions
    assert_no_statsd_calls do
      assert_raises do
        ToBeInstrumented.to_raise_too
      end
    end
  end

  def test_instrumented_class_method_add_suffix_on_exceptions
    assert_statsd_increment('to_raise_too_with_suffix.StandardError') do
      assert_raises do
        ToBeInstrumented.to_raise_too_with_suffix
      end
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

  def test_instance_method_preserved_visibility
    assert ToBeInstrumented.private_method_defined?(:i_am_private)
    refute ToBeInstrumented.protected_method_defined?(:i_am_private)
    refute ToBeInstrumented.public_method_defined?(:i_am_private)

    refute ToBeInstrumented.private_method_defined?(:i_am_protected)
    assert ToBeInstrumented.protected_method_defined?(:i_am_protected)
    refute ToBeInstrumented.public_method_defined?(:i_am_protected)

    refute ToBeInstrumented.private_method_defined?(:to_be_counted)
    refute ToBeInstrumented.protected_method_defined?(:to_be_counted)
    assert ToBeInstrumented.public_method_defined?(:to_be_counted)
  end

  def test_class_methods_preserved_visibility
    assert ToBeInstrumented.singleton_class.private_method_defined?(:i_am_private_too)
    refute ToBeInstrumented.singleton_class.protected_method_defined?(:i_am_private_too)
    refute ToBeInstrumented.singleton_class.public_method_defined?(:i_am_private_too)

    refute ToBeInstrumented.singleton_class.private_method_defined?(:i_am_protected_too)
    assert ToBeInstrumented.singleton_class.protected_method_defined?(:i_am_protected_too)
    refute ToBeInstrumented.singleton_class.public_method_defined?(:i_am_protected_too)

    refute ToBeInstrumented.singleton_class.private_method_defined?(:to_be_counted_too)
    refute ToBeInstrumented.singleton_class.protected_method_defined?(:to_be_counted_too)
    assert ToBeInstrumented.singleton_class.public_method_defined?(:to_be_counted_too)
  end
end
