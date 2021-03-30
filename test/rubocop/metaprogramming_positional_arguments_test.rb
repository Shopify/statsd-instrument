# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class MetaprogrammingPositionalArgumentsTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::MetaprogrammingPositionalArguments.new
    end

    def test_ok_with_two_arguments
      assert_no_offenses("ClassName.statsd_count_if(:method, 'metric') { foo }")
      assert_no_offenses("ClassName.statsd_measure :method, 'metric'")
      assert_no_offenses(<<~RUBY)
        class Foo
          statsd_count :method, 'metric'
        end
      RUBY
    end

    def test_ok_with_keyword_arguments_and_blocks
      assert_no_offenses("ClassName.statsd_measure :method, 'metric', foo: 'bar'")
      assert_no_offenses("ClassName.statsd_count_success(:method, 'metric', **kwargs)")
      assert_no_offenses("ClassName.statsd_measure(:method, 'metric', foo: 'bar', &block)")
      assert_no_offenses(<<~RUBY)
        class Foo
          statsd_count_if(:method, 'metric', foo: 'bar', baz: 'quc') do |result|
            result == 'ok'
          end
        end
      RUBY
    end

    def test_offense_with_positional_arguments
      assert_offense("ClassName.statsd_measure(:method, 'metric', 1)")
      assert_offense("ClassName.statsd_measure(:method, 'metric', 1, ['tag'])")
      assert_offense("ClassName.statsd_measure(:method, 'metric', 1, tag: 'value')")
      assert_offense(<<~RUBY)
        class Foo
          extend StatsD::Instrument
          statsd_measure(:method, 'metric', 1)
        end
      RUBY
    end

    def test_offense_with_splat
      assert_offense("ClassName.statsd_measure(:method, 'metric', *options)")
    end

    def test_offense_with_constant_or_method_as_third_argument
      assert_offense("ClassName.statsd_measure(:method, 'metric', SAMPLE_RATE_CONSTANT)")
      assert_offense("ClassName.statsd_measure(:method, 'metric', method_returning_a_hash)")
    end
  end
end
