# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require 'statsd/instrument/rubocop/positional_arguments'

module Rubocop
  class PositionalArgumentsTest < Minitest::Test
    attr_reader :cop

    def setup
      @cop = RuboCop::Cop::StatsD::PositionalArguments.new
    end

    def test_no_offenses
      assert_no_offenses("StatsD.increment 'foo'")
      assert_no_offenses("StatsD.gauge('foo', 2)")
      assert_no_offenses("StatsD.increment('foo', 2, tags: ['foo:bar'])")
      assert_no_offenses("StatsD.increment('foo', 2, sample_rate: 0.1, tags: { foo: 'bar' })")
      assert_no_offenses("StatsD.increment('foo', 2) { foo }")
      assert_no_offenses("StatsD.increment('foo', 2, &block)")
    end

    def test_no_offense_for_now
      assert_no_offenses("StatsD.increment 'foo', value: 3")
      assert_no_offenses("StatsD.increment 'foo', value: 3, sample_rate: 0.5")
      assert_no_offenses("StatsD.increment('foo', value: 3, tags: ['foo']) { foo }")
    end

    def test_autocorrect_only_sample_rate
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5)")
      assert_equal "StatsD.increment('foo', 2, sample_rate: 0.5)", corrected
    end

    def test_autocorrect_only_tags
      corrected = autocorrect_source("StatsD.increment('foo', 2, nil, ['foo', 'bar'])")
      assert_equal "StatsD.increment('foo', 2, tags: ['foo', 'bar'])", corrected
    end

    def test_autocorrect_sample_rate_and_tags_as_array
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, ['foo', 'bar'])")
      assert_equal "StatsD.increment('foo', 2, sample_rate: 0.5, tags: ['foo', 'bar'])", corrected
    end

    def test_autocorrect_sample_rate_and_tags_as_hash_with_curly_braces
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, { foo: 'bar' })")
      assert_equal "StatsD.increment('foo', 2, sample_rate: 0.5, tags: { foo: 'bar' })", corrected
    end

    def test_autocorrect_sample_rate_and_tags_as_hash_without_curly_braces
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, foo: 'bar')")
      assert_equal "StatsD.increment('foo', 2, sample_rate: 0.5, tags: { foo: 'bar' })", corrected
    end

    def test_autocorrect_sample_rate_and_block_pass
      corrected = autocorrect_source("StatsD.distribution('foo', 2, 0.5, &block)")
      assert_equal "StatsD.distribution('foo', 2, sample_rate: 0.5, &block)", corrected
    end

    def test_autocorrect_sample_rate_tags_and_block_pass
      corrected = autocorrect_source("StatsD.measure('foo', 2, nil, foo: 'bar', &block)")
      assert_equal "StatsD.measure('foo', 2, tags: { foo: 'bar' }, &block)", corrected
    end

    def test_autocorrect_sample_rate_and_curly_braces_block
      corrected = autocorrect_source("StatsD.measure('foo', 2, 0.5) { foo }")
      assert_equal "StatsD.measure('foo', 2, sample_rate: 0.5) { foo }", corrected
    end

    def test_autocorrect_sample_rate_and_do_end_block
      corrected = autocorrect_source(<<~RUBY)
        StatsD.distribution 'foo', 124, 0.6, ['bar'] do
          foo
        end
      RUBY
      assert_equal <<~RUBY, corrected
        StatsD.distribution 'foo', 124, sample_rate: 0.6, tags: ['bar'] do
          foo
        end
      RUBY
    end

    private

    def assert_no_offenses(source)
      corrected = autocorrect_source(source)
      assert_equal(source, corrected, "An unexpected offense was detected and corrected")
    end

    def autocorrect_source(source)
      RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
      RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
      cop.instance_variable_get(:@options)[:auto_correct] = true
      processed_source = RuboCop::ProcessedSource.new(source, 2.3, nil)
      investigate(cop, processed_source)

      corrector = RuboCop::Cop::Corrector.new(processed_source.buffer, cop.corrections)
      corrector.rewrite
    end

    def investigate(cop, processed_source)
      forces = RuboCop::Cop::Force.all.each_with_object([]) do |klass, instances|
        next unless cop.join_force?(klass)
        instances << klass.new([cop])
      end

      commissioner = RuboCop::Cop::Commissioner.new([cop], forces, raise_error: true)
      commissioner.investigate(processed_source)
      commissioner
    end
  end
end
