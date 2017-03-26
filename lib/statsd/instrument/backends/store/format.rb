module StatsD::Instrument::Backends::Store
  module Format
    NAME_RECORD = -1
    TIME_RECORD = -2
    TYPE_TEMPLATE = {
      c:  'l',
      ms: 'f',
      g:  'f',
      h:  'f',
    }
  end
end

