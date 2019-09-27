# frozen_string_literal: true

class StatsD::Instrument::NullSink
  def <<(_datagram)
    self # noop
  end
end
