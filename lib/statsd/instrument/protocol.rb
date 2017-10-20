module StatsD::Instrument::Protocol
  extend self

  def protocol_from_name(name)
    case name
    when "datadog"
      StatsD::Instrument::Protocols::Datadog.new
    when "statsite"
      StatsD::Instrument::Protocols::Statsite.new
    when "etsy"
      StatsD::Instrument::Protocols::Etsy.new
    end
  end
end

require 'statsd/instrument/protocols/datadog'
require 'statsd/instrument/protocols/etsy'
require 'statsd/instrument/protocols/statsite'
