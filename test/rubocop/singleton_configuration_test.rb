# frozen_string_literal: true

require "test_helper"
require "statsd/instrument/rubocop"

module Rubocop
  class SingletonConfigurationTest < Minitest::Test
    include RubocopHelper

    def setup
      @cop = RuboCop::Cop::StatsD::SingletonConfiguration.new
    end

    def test_offense_statsd_backend
      assert_offense('StatsD.backend = "foo"')
      assert_offense("old_backend = StatsD.backend")
    end

    def test_offense_statsd_prefix
      assert_offense('StatsD.prefix = "foo"')
      assert_offense('"#{StatsD.prefix}.foo"')
    end

    def test_offense_statsd_default_tags
      assert_offense('StatsD.default_tags = ["foo"]')
      assert_offense("StatsD.default_tags.empty?")
    end

    def test_offense_statsd_default_sample_rate
      assert_offense("StatsD.default_sample_rate = 1.0")
      assert_offense("should_sample = StatsD.default_sample_rate > rand")
    end

    def test_no_offense_for_other_methods
      assert_no_offenses("StatsD.singleton_client = my_client")
      assert_no_offenses('StatsD.logger.info("foo")')
    end

    def test_no_offense_for_constant_reference
      assert_no_offenses("legacy_client = StatsD")
    end
  end
end
