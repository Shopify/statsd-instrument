# frozen_string_literal: true

require 'rubocop'

module RubocopHelper
  attr_accessor :cop

  private

  def assert_no_offenses(source)
    investigate(RuboCop::ProcessedSource.new(source, 2.3, nil))
    assert_predicate cop.offenses, :empty?, "Did not expect Rubocop to find offenses"
  end

  def assert_offense(source)
    investigate(RuboCop::ProcessedSource.new(source, 2.3, nil))
    refute_predicate cop.offenses, :empty?, "Expected Rubocop to find offenses"
  end

  def assert_no_autocorrect(source)
    corrected = autocorrect_source(source)
    assert_equal source, corrected
  end

  def autocorrect_source(source)
    RuboCop::Formatter::DisabledConfigFormatter.config_to_allow_offenses = {}
    RuboCop::Formatter::DisabledConfigFormatter.detected_styles = {}
    cop.instance_variable_get(:@options)[:auto_correct] = true

    processed_source = RuboCop::ProcessedSource.new(source, 2.3, nil)
    investigate(processed_source)

    corrector = RuboCop::Cop::Corrector.new(processed_source.buffer, cop.corrections)
    corrector.rewrite
  end

  def investigate(processed_source)
    forces = RuboCop::Cop::Force.all.each_with_object([]) do |klass, instances|
      next unless cop.join_force?(klass)
      instances << klass.new([cop])
    end

    commissioner = RuboCop::Cop::Commissioner.new([cop], forces, raise_error: true)
    commissioner.investigate(processed_source)
    commissioner
  end
end
