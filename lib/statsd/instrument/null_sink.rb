# frozen_string_literal: true

class StatsD::Instrument::NullSink
  def <<(datagram)
    # noop
  end
end
