# frozen_string_literal: true

# The Datagram class parses and inspects a StatsD datagrans
class StatsD::Instrument::Datagram
  attr_reader :source

  def initialize(source)
    @source = source
  end

  # @return [Float] The sample rate at which this datagram was emitted, between 0 and 1.
  def sample_rate
    parsed_datagram[:sample_rate] ? Float(parsed_datagram[:sample_rate]) : 1.0
  end

  def type
    parsed_datagram[:type]
  end

  def name
    parsed_datagram[:name]
  end

  def value
    parsed_datagram[:value]
  end

  def tags
    @tags ||= parsed_datagram[:tags] ? parsed_datagram[:tags].split(',') : nil
  end

  def inspect
    "#<#{self.class.name}:\"#{@source}\">"
  end

  def hash
    source.hash
  end

  def eql?(other)
    case other
    when StatsD::Instrument::Datagram
      source == other.source
    when String
      source == other
    else
      false
    end
  end

  alias_method :==, :eql?

  private

  PARSER = %r{
    \A
    (?<name>[^\:\|\@]+)\:(?<value>[^\:\|\@]+)\|(?<type>c|ms|g|s|h|d)
    (?:\|\@(?<sample_rate>\d*(?:\.\d*)?))?
    (?:\|\#(?<tags>(?:[^\|\#,]+(?:,[^\|\#,]+)*)))?
    \n? # In some implementations, the datagram may include a trailing newline.
    \z
  }x
  private_constant :PARSER

  def parsed_datagram
    @parsed ||= if (match_info = PARSER.match(@source))
      match_info
    else
      raise ArgumentError, "Invalid StatsD datagram: #{@source}"
    end
  end
end
