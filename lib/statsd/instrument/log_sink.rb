# frozen_string_literal: true

class StatsD::Instrument::LogSink
  attr_reader :logger, :severity

  def initialize(logger, severity: Logger::DEBUG)
    @logger = logger
    @severity = severity
  end

  def <<(datagram)
    # Some implementations require a newline at the end of datagrams.
    # When logging, we make sure those newlines are removed using chomp.

    logger.add(severity, "[StatsD] #{datagram.chomp}")
    self
  end
end
