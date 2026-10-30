# frozen_string_literal: true

require "test_helper"

class ValueFormatterTest < Minitest::Test
  def test_formats_floats_with_15_significant_digits
    assert_equal("0.812345678901235", StatsD::Instrument::ValueFormatter.format(0.8123456789012345))
    assert_equal("0.3", StatsD::Instrument::ValueFormatter.format(0.30000000000000004))
    assert_equal("122.54", StatsD::Instrument::ValueFormatter.format(122.54))
  end

  def test_formatted_floats_parse_back_to_nearly_the_same_value
    [0.0031234567891234567, 0.8123456789012345, 45.12345678901234, 123_456.78901234567, -12.3456789].each do |value|
      assert_in_delta(value, Float(StatsD::Instrument::ValueFormatter.format(value)), value.abs * 1e-14)
    end
  end

  def test_keeps_the_usual_formatting_for_whole_floats
    assert_equal("100.0", StatsD::Instrument::ValueFormatter.format(100.0))
    assert_equal("-3.0", StatsD::Instrument::ValueFormatter.format(-3.0))
  end

  def test_keeps_the_usual_formatting_for_non_finite_floats
    assert_equal("Infinity", StatsD::Instrument::ValueFormatter.format(Float::INFINITY))
    assert_equal("-Infinity", StatsD::Instrument::ValueFormatter.format(-Float::INFINITY))
    assert_equal("NaN", StatsD::Instrument::ValueFormatter.format(Float::NAN))
  end

  def test_formats_other_values_with_to_s
    assert_equal("42", StatsD::Instrument::ValueFormatter.format(42))
    assert_equal("abc", StatsD::Instrument::ValueFormatter.format("abc"))
  end
end
