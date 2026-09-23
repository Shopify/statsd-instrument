# frozen_string_literal: true

require "test_helper"

class SanitizationTest < Minitest::Test
  def test_clean_input_is_returned_without_copying_or_freezing
    [:name, :tag, :service_check_message].each do |method|
      mutable = +"café.safe_value"
      assert_same(mutable, StatsD::Instrument::Sanitization.public_send(method, mutable))
      refute_predicate(mutable, :frozen?)
      assert_same(mutable.freeze, StatsD::Instrument::Sanitization.public_send(method, mutable))
    end
  end

  def test_name_replaces_each_ascii_whitespace_and_protocol_delimiter
    [" ", "\t", "\n", "\r", "\f", "\v", ":", "|", "@"].each do |character|
      name = +"prefix.#{character}my#{character}value"
      expected_original = name.dup
      assert_equal("prefix._my_value", StatsD::Instrument::Sanitization.name(name))
      assert_equal(expected_original, name)
      refute_predicate(name, :frozen?)
    end
    assert_equal("name___value", StatsD::Instrument::Sanitization.name("name \t\nvalue"))
  end

  def test_name_does_not_expand_whitespace_matching_to_unicode
    name = "café\u00a0value"
    assert_same(name, StatsD::Instrument::Sanitization.name(name))
  end

  def test_tags_and_values_keep_ordinary_whitespace
    text = "hello \tworld\f\v"
    [:tag, :service_check_message].each do |method|
      assert_same(text, StatsD::Instrument::Sanitization.public_send(method, text))
    end
  end

  def test_each_field_preserves_its_existing_replacement_rules
    sanitizer = StatsD::Instrument::Sanitization
    assert_equal("tag:value", sanitizer.tag("tag:va|,\r\nlue"))
    assert_equal("hello world____", sanitizer.service_check_message("hello world:|@\n"))
  end

  def test_compiled_name_helper_returns_clean_input_unchanged
    name = +"name"
    assert_same(name, StatsD::Instrument::CompiledMetric::DatagramBlueprintBuilder.normalize_name(name))
    refute_predicate(name, :frozen?)
  end
end
