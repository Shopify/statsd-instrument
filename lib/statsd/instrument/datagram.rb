# frozen_string_literal: true

class StatsD::Instrument::Datagram
  attr_reader :source

  def initialize(source)
    @source = source
  end

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
    parsed_datagram[:tags] ? parsed_datagram[:tags].split(',') : nil
  end

  def inspect
    "#<#{self.class.name}:\"#{@source}\">"
  end

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
