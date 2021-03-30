# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class MetricReturnValueTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::MetricReturnValue.new
    end

    def test_ok_for_non_metric_method
      assert_no_offenses("backend = StatsD.backend")
    end

    def test_ok_as_naked_statement
      assert_no_offenses("StatsD.increment('foo')")
      assert_no_offenses("StatsD.measure('foo') { foo }")
    end

    def test_ok_as_multiple_statement
      assert_no_offenses(<<~RUBY)
        StatsD.increment 'foo'
        StatsD.increment 'bar'
      RUBY
    end

    def test_ok_inside_block
      assert_no_offenses(<<~RUBY)
        block do
          StatsD.measure
        end
      RUBY
    end

    def test_ok_when_passing_a_block_as_param
      assert_no_offenses("block_result = StatsD.measure('foo', &block)")
    end

    def test_ok_when_passing_a_curly_braces_block
      assert_no_offenses("block_result = StatsD.measure('foo') { measure_me }")
    end

    def test_ok_when_passing_do_end_block
      assert_no_offenses(<<~RUBY)
        block_result = StatsD.measure('foo') do
          return_something_useful
        end
      RUBY
    end

    def test_offense_in_assignment
      assert_offense("metric = StatsD.increment('foo')")
    end

    def test_offense_in_multi_assignment
      assert_offense("foo, metric = bar, StatsD.increment('foo')")
    end

    def test_offense_in_hash
      assert_offense("{ metric: StatsD.increment('foo') }")
    end

    def test_offense_in_method_call
      assert_offense("process(StatsD.increment('foo'))")
    end

    def test_offense_when_returning
      assert_offense("return StatsD.increment('foo')")
    end

    def test_offense_when_yielding
      assert_offense("yield StatsD.increment('foo')")
    end
  end
end
