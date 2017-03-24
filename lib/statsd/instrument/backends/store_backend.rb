require 'statsd/instrument/backends/store/packer'
require 'monitor'
require 'time'
require 'fileutils'

module StatsD::Instrument::Backends
  class StoreBackend < StatsD::Instrument::Backend
    Packer = StatsD::Instrument::Backends::Store::Packer
    TIME_ACCURANCY = 1 # second(s)
    include MonitorMixin

    def initialize(dir_or_io = "/tmp/instrument-statsd")
      super()
      @dir_or_io = dir_or_io
      @io = nil
      reopen
    end

    def reopen
      if @dir_or_io.respond_to? :write
        @io = @dir_or_io
        @next_reopen = false
      else
        @next_reopen = Time.parse("24:00").to_i
        dirname = Time.now.strftime("%Y-%m-%d")
        basedir = File.join(@dir_or_io, dirname)
        FileUtils.mkdir_p basedir
        @io.close if @io
        @io = File.open(File.join(basedir, "#{$$}.statsb"), 'ab')
        @io.write('STATSBv1') if @io.stat.size == 0
      end
      @names = {}
      @next_id = 1
      @last_time = 0
    end

    def collect_metric(m)
      if m.sample_rate < 1.0 && rand > m.sample_rate
        return false
      end

      synchronize do
        reopen if @next_reopen && Time.now.to_i > @next_reopen

        id = @names[m.name]
        unless id
          id = @names[m.name] = @next_id
          @io.write(Packer::pack_name(id, m.name, m.type))
          @next_id += 1
        end
        time = Time.now.to_i
        if (time - @last_time) > TIME_ACCURANCY
          @io.write(Packer::pack_time(time))
          @last_time = time
        end
        @io.write(Packer::pack_metric(id, m.value, m.type))
      end
    end
  end
end
