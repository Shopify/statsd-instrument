# frozen_string_literal: true

require "rspec/expectations"
require "rspec/core/version"

module StatsD
  module Instrument
    module Matchers
      class Matcher
        include(RSpec::Matchers::Composable) if RSpec::Core::Version::STRING.start_with?("3")
        include StatsD::Instrument::Helpers

        def initialize(metric_type, metric_name, options = {})
          @metric_type = metric_type
          @metric_name = metric_name
          @options = options
        end

        def matches?(block)
          expect_statsd_call(@metric_type, @metric_name, @options, &block)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          @message = e.message
          false
        end

        def failure_message
          @message
        end

        def failure_message_when_negated
          "No StatsD calls for metric #{@metric_name} expected."
        end

        def supports_block_expectations?
          true
        end

        def description
          "trigger a statsd call for metric #{@metric_name}"
        end

        private

        def expect_statsd_call(metric_type, metric_name, options, &block)
          metrics = capture_statsd_calls(&block)
          metrics = metrics.select do |m|
            metric_tags = m.tags || []
            options_tags = options[:tags]
            tag_matches = options_tags.nil? || RSpec::Matchers::BuiltIn::Match.new(options_tags).matches?(metric_tags)
            m.type == metric_type && m.name == metric_name && tag_matches
          end

          if metrics.empty?
            raise RSpec::Expectations::ExpectationNotMetError, "No StatsD calls for metric #{metric_name} were made."
          elsif options[:times] && options[:times] != metrics.length
            raise RSpec::Expectations::ExpectationNotMetError, "The numbers of StatsD calls for metric " \
              "#{metric_name} was unexpected. Expected #{options[:times].inspect}, got #{metrics.length}"
          end

          [:sample_rate, :value, :tags].each do |expectation|
            next unless options[expectation]

            num_matches = metrics.count do |m|
              matcher = RSpec::Matchers::BuiltIn::Match.new(options[expectation])
              matcher.matches?(m.public_send(expectation))
            end

            found = options[:times] ? num_matches == options[:times] : num_matches > 0

            unless found
              message = metric_information(metric_name, options, metrics, expectation)
              raise RSpec::Expectations::ExpectationNotMetError, message
            end
          end

          true
        end

        def metric_information(metric_name, options, metrics, expectation)
          message = "expected StatsD #{expectation.inspect} for metric '#{metric_name}' to be called"

          message += "\n  "
          message += options[:times] ? "exactly #{options[:times]} times" : "at least once"
          message += " with: #{options[expectation]}"

          message += "\n  captured metric values: #{metrics.map(&expectation).join(", ")}"

          message
        end
      end

      Increment = Class.new(Matcher)
      Measure = Class.new(Matcher)
      Gauge = Class.new(Matcher)
      Set = Class.new(Matcher)
      Histogram = Class.new(Matcher)
      Distribution = Class.new(Matcher)

      def trigger_statsd_increment(metric_name, options = {})
        Increment.new(:c, metric_name, options)
      end

      def trigger_statsd_measure(metric_name, options = {})
        Measure.new(:ms, metric_name, options)
      end

      def trigger_statsd_gauge(metric_name, options = {})
        Gauge.new(:g, metric_name, options)
      end

      def trigger_statsd_set(metric_name, options = {})
        Set.new(:s, metric_name, options)
      end

      def trigger_statsd_histogram(metric_name, options = {})
        Histogram.new(:h, metric_name, options)
      end

      def trigger_statsd_distribution(metric_name, options = {})
        Distribution.new(:d, metric_name, options)
      end
    end
  end
end
