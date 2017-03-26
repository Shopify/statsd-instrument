require 'statsd/instrument/backends/store/format'

module StatsD::Instrument::Backends::Store
  class Packer
    extend Format

    TYPE_TEMPLATE_PACK = Hash[ StatsD::Instrument::Backends::Store::Format::TYPE_TEMPLATE.collect {|k,v| [k, "s#{v}"] } ]

    class << self
      def pack_name id, name, type
        [NAME_RECORD, id, name.size, name, type.to_s].pack("sssA*A2")
      end

      def pack_time time
        [TIME_RECORD, time].pack("sL")
      end

      def pack_metric id, value, type
        raise "Type #{type} not supported by store backend" unless pack_str = TYPE_TEMPLATE_PACK[type]
        [id, value].pack(pack_str)
      end
    end
  end
end
