# frozen_string_literal: true

class StatsD::Instrument::CaptureSink
  attr_reader :parent, :datagrams, :datagram_class

  def initialize(parent:, datagram_class: StatsD::Instrument::Datagram)
    @parent = parent
    @datagram_class = datagram_class
    @datagrams = []
  end

  def <<(datagram)
    @datagrams << datagram_class.new(datagram)
    parent << datagram
    self
  end

  def clear
    @datagrams.clear
  end
end
