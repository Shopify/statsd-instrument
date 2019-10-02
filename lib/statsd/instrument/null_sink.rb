# frozen_string_literal: true

# @note This class is part of the new Client implementation that is intended
#   to become the new default in the next major release of this library.
class StatsD::Instrument::NullSink
  def sample?(_sample_rate)
    false
  end

  def <<(_datagram)
    self # noop
  end
end
