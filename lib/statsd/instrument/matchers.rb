require 'rspec/expectations'
require 'rspec/core/version'

module StatsD::Instrument::Matchers
  CUSTOM_MATCHERS = {
    increment: :c,
    measure: :ms,
    gauge: :g,
    histogram: :h,
    set: :s,
    key_value: :kv
  }

  class Matcher
    include RSpec::Matchers::Composable if RSpec::Core::Version::STRING.start_with?('3')
    include StatsD::Instrument::Helpers

    def initialize(metric_type, metric_name, options = {})
      @metric_type = metric_type
      @metric_name = metric_name
      @options = options
    end

    def matches?(block)
      begin
        expect_statsd_call(@metric_type, @metric_name, @options, &block)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        @message = e.message

        false
      end
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

    private

    def expect_statsd_call(metric_type, metric_name, options, &block)
      metrics = capture_statsd_calls(&block)
      metrics = metrics.select { |m| m.type == metric_type && m.name == metric_name }

      raise RSpec::Expectations::ExpectationNotMetError, "No StatsD calls for metric #{metric_name} were made." if metrics.empty?
      raise RSpec::Expectations::ExpectationNotMetError, "The numbers of StatsD calls for metric #{metric_name} was unexpected. Expected #{options[:times].inspect}, got #{metrics.length}" if options[:times] && options[:times] != metrics.length

      [:sample_rate, :value, :tags].each do |expectation|
        next unless options[expectation]

        num_matches = metrics.count { |m| m.public_send(expectation) == options[expectation] }
        found = options[:times] ? num_matches == options[:times] : num_matches > 0

        if !found
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

      message += "\n  captured metric values: #{metrics.map(&expectation).join(', ')}"

      message
    end
  end

  CUSTOM_MATCHERS.each do |method_name, metric_type|
    klass = Class.new(Matcher)

    define_method "trigger_statsd_#{method_name}" do |metric_name, options = {}|
      klass.new(metric_type, metric_name, options)
    end

    StatsD::Instrument::Matchers.const_set(method_name.capitalize, klass)
  end
end
