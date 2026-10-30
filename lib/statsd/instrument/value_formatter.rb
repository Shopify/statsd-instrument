# frozen_string_literal: true

module StatsD
  module Instrument
    # Formats metric values for datagrams.
    module ValueFormatter
      FLOAT_FORMAT = "%.15g"
      private_constant :FLOAT_FORMAT

      class << self
        # Float#to_s searches for the shortest representation that round-trips exactly, which is slow for values with
        # many significant digits, like measured durations. 15 significant digits is as many as a Float reliably holds,
        # so the value the receiver parses is the same to within about 1e-15, relative. Whole numbers and non-finite
        # values are already fast to format, so they keep their usual formatting.
        def format(value)
          if value.is_a?(Float) && value.finite? && value % 1 != 0
            FLOAT_FORMAT % value
          else
            value.to_s
          end
        end
      end
    end
  end
end
