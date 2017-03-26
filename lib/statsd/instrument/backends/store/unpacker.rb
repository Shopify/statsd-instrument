require 'statsd/instrument/backends/store/format'

module StatsD::Instrument::Backends::Store
  class Unpacker
    include Format

    def initialize io
      @io = io
      raise "Not a statsb file" if @io.read(8) != "STATSBv1"
      @names = []
    end

    def unpack_time
      @time = Time.at(@io.read(4).unpack('L').first)
    end

    def unpack_name
      id, name_len = @io.read(4).unpack('ss')
      name, type = @io.read(name_len + 2).unpack("A#{name_len}A2")
      type = type.rstrip.to_sym
      @names[id] = [name, type]
    end

    def unpack_metric id
      name, type = @names[id]
      value = @io.read(4).unpack(TYPE_TEMPLATE[type]).first
      "#{name}:#{value}|#{type}"
    end

    def next_record
      case type = @io.read(2).unpack('s').first
      when TIME_RECORD
        unpack_time
      when NAME_RECORD
        unpack_name
      else
        unpack_metric type
      end
    end

    def next_metric
      loop do
        result = next_record
        return result if result.is_a? String
        return nil if @io.eof?
      end
    end
  end
end
