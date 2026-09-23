# frozen_string_literal: true

module StatsD
  module Instrument
    # Field-specific wire normalization. Clean strings are returned unchanged;
    # callers retaining a frozen value must take ownership themselves.
    # @api private
    module Sanitization
      # Hot serializers use these same rules inline to avoid per-field Ruby calls.
      NAME_PATTERN = /[:|@\s]/.freeze
      NAME_CHARACTERS = ":|@ \t\r\n\f\v"
      TAG_PATTERN = /[|,\r\n]/.freeze
      TAG_CHARACTERS = "|,\r\n"

      class << self
        # Replace each ASCII whitespace or protocol delimiter with one underscore.
        # @return [String] The original string if clean, otherwise a new string.
        def name(string)
          NAME_PATTERN.match?(string) ? string.tr(NAME_CHARACTERS, "_") : string
        end

        # Tag components allow spaces and colons, but not field/tag separators.
        def tag(string)
          TAG_PATTERN.match?(string) ? string.tr(TAG_CHARACTERS, "") : string
        end

        # Keep message whitespace intact; this is not a metric name.
        def service_check_message(string)
          /[:|@\r\n]/.match?(string) ? string.tr(":|@\r\n", "_") : string
        end
      end
    end
  end
end
