# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class PositionalArgumentsTest < Minitest::Test
    include RubocopHelper

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
      assert_no_offenses("StatsD.gauge('foo', 2, **kwargs)")
    end

    def test_no_offense_for_now_when_using_value_keyword_argument
      assert_no_offenses("StatsD.increment 'foo', value: 3")
      assert_no_offenses("StatsD.increment 'foo', value: 3, sample_rate: 0.5")
      assert_no_offenses("StatsD.increment('foo', value: 3, tags: ['foo']) { foo }")
    end

    def test_offense_when_using_method_or_constant
      assert_offense("StatsD.gauge('foo', 2, SAMPLE_RATE_CONSTANT)")
      assert_offense("StatsD.gauge('foo', 2, method_returning_a_hash)")
    end

    def test_offense_when_using_local_variable
      assert_offense("lambda { |x| StatsD.gauge('foo', 2, x) }")
      assert_offense(<<~RUBY)
        x = foo
        StatsD.gauge('foo', 2, x)
      RUBY
    end

    def test_offense_when_using_splat
      assert_offense("StatsD.gauge('foo', 2, *options)")
    end

    def test_no_autocorrect_when_using_method_or_constant
      assert_no_autocorrect("StatsD.gauge('foo', 2, SAMPLE_RATE_CONSTANT)")
      assert_no_autocorrect("StatsD.gauge('foo', 2, method_returning_a_hash)")
    end

    def test_autocorrect_only_sample_rate
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5)")
      assert_equal("StatsD.increment('foo', 2, sample_rate: 0.5)", corrected)
    end

    def test_autocorrect_only_sample_rate_as_int
      corrected = autocorrect_source("StatsD.increment('foo', 2, 1)")
      assert_equal("StatsD.increment('foo', 2, sample_rate: 1)", corrected)
    end

    def test_autocorrect_only_tags
      corrected = autocorrect_source("StatsD.increment('foo', 2, nil, ['foo', 'bar'])")
      assert_equal("StatsD.increment('foo', 2, tags: ['foo', 'bar'])", corrected)
    end

    def test_autocorrect_sample_rate_and_tags_as_array
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, ['foo', 'bar'])")
      assert_equal("StatsD.increment('foo', 2, sample_rate: 0.5, tags: ['foo', 'bar'])", corrected)
    end

    def test_autocorrect_sample_rate_and_tags_as_hash_with_curly_braces
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, { foo: 'bar' })")
      assert_equal("StatsD.increment('foo', 2, sample_rate: 0.5, tags: { foo: 'bar' })", corrected)
    end

    def test_autocorrect_sample_rate_and_tags_as_hash_without_curly_braces
      corrected = autocorrect_source("StatsD.increment('foo', 2, 0.5, foo: 'bar')")
      assert_equal("StatsD.increment('foo', 2, sample_rate: 0.5, tags: { foo: 'bar' })", corrected)
    end

    def test_autocorrect_sample_rate_and_block_pass
      corrected = autocorrect_source("StatsD.distribution('foo', 2, 0.5, &block)")
      assert_equal("StatsD.distribution('foo', 2, sample_rate: 0.5, &block)", corrected)
    end

    def test_autocorrect_sample_rate_tags_and_block_pass
      corrected = autocorrect_source("StatsD.measure('foo', 2, nil, foo: 'bar', &block)")
      assert_equal("StatsD.measure('foo', 2, tags: { foo: 'bar' }, &block)", corrected)
    end

    def test_autocorrect_sample_rate_and_curly_braces_block
      corrected = autocorrect_source("StatsD.measure('foo', 2, 0.5) { foo }")
      assert_equal("StatsD.measure('foo', 2, sample_rate: 0.5) { foo }", corrected)
    end

    def test_autocorrect_sample_rate_and_do_end_block
      corrected = autocorrect_source(<<~RUBY)
        StatsD.distribution 'foo', 124, 0.6, ['bar'] do
          foo
        end
      RUBY
      assert_equal(<<~RUBY, corrected)
        StatsD.distribution 'foo', 124, sample_rate: 0.6, tags: ['bar'] do
          foo
        end
      RUBY
    end
  end
end
