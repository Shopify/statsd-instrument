# frozen_string_literal: true

class StatsD::Instrument::CaptureSink
  attr_reader :parent, :datagrams

  def initialize(parent:)
    @parent = parent
    @datagrams = []
  end

  def <<(datagram)
    @datagrams << StatsD::Instrument::Datagram.new(datagram)
    parent << datagram
    self
  end

  def clear
    @datagrams.clear
  end
end
