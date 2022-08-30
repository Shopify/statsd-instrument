# frozen_string_literal: true

require "test_helper"

class ChangelogTest < Minitest::Test
  def test_has_heading_for_current_version
    assert_includes(changelog_headings, current_version_heading)
  end

  def test_headings_are_consistent
    invalid_headings = changelog_headings.reject do |heading|
      next true if heading == "# Changelog"
      next true if heading == "## Unreleased changes"

      # Remaining headings are <h2> if and only if they are version headings, and must be formatted correctly.
      if heading.start_with?("## ") || heading.include?("Version")
        next heading.match?(/^## Version \d+\.\d+\.\d+/)
      end

      next true if heading.start_with?("###") # <h3> and lower are permitted

      false # All other headings are forbidden
    end

    assert_empty(invalid_headings, "Headings must follow formatting conventions")
  end

  private

  def current_version_heading
    "## Version #{StatsD::Instrument::VERSION}"
  end

  def changelog_headings
    File.read("CHANGELOG.md").each_line.grep(/^#/).map(&:strip)
  end
end
