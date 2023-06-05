# frozen_string_literal: true

require "rubocop"
require "rubocop/cop/legacy/corrector"

module RubocopHelper
  attr_accessor :cop

  private

  RUBY_VERSION = 2.5
  private_constant :RUBY_VERSION

  def assert_no_offenses(source)
    report = investigate(RuboCop::ProcessedSource.new(source, RUBY_VERSION, nil))
    assert_predicate(report.offenses, :empty?, "Did not expect Rubocop to find offenses")
  end

  def assert_offense(source)
    report = investigate(RuboCop::ProcessedSource.new(source, RUBY_VERSION, nil))
    refute_predicate(report.offenses, :empty?, "Expected Rubocop to find offenses")
  end

  def assert_no_autocorrect(source)
    corrected = autocorrect_source(source)
    assert_equal(source, corrected)
  end

  def autocorrect_source(source)
    RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
    RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
    cop.instance_variable_get(:@options)[:autocorrect] = true
    cop.instance_variable_get(:@options)[:raise_error] = true

    processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION, nil)
    report = investigate(processed_source)
    corrector = RuboCop::Cop::Legacy::Corrector.new(
      processed_source.buffer,
      correctors(report),
    )
    corrector.process
  end

  def correctors(report)
    correctors = report.correctors.reject(&:nil?)
    if correctors.empty?
      return []
    end

    corrections_proxy = RuboCop::Cop::Legacy::CorrectionsProxy.new(correctors.first)
    correctors.drop(1).each { |c| corrections_proxy.concat(c) }
    corrections_proxy
  end

  def investigate(processed_source)
    forces = RuboCop::Cop::Force.all.each_with_object([]) do |klass, instances|
      instances << klass.new([cop])
    end

    commissioner = RuboCop::Cop::Commissioner.new([cop], forces)
    commissioner.investigate(processed_source)
  end
end
