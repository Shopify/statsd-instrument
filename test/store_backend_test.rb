require 'test_helper'
require 'statsd/instrument/backends/store/unpacker'
require 'time'
require 'fileutils'

class StoreBackendTest < Minitest::Test
  A_TIME = 1368471660
  def setup
    @io = StringIO.new
    @backend = StatsD::Instrument::Backends::StoreBackend.new(@io)
    Time.stubs(:now).returns(Time.at(A_TIME))
  end

  def test_store_c1
    m = StatsD::Instrument::Metric::new(type: :c, name: 'mock.c1')
    @backend.collect_metric(m)
    assert_equal [-1, 1, 7, "mock.c1", "c", -2, A_TIME, 1, 1], @io.string.unpack("sssA7A2sLsl")
  end

  def test_store_c2
    m = StatsD::Instrument::Metric::new(type: :c, name: 'mock.c2', value: 2)
    @backend.collect_metric(m)
    assert_equal [-1, 1, 7, "mock.c2", "c", -2, A_TIME, 1, 2], @io.string.unpack("sssA7A2sLsl")
  end

  def test_store_ms
    m = StatsD::Instrument::Metric::new(type: :ms, name: 'mock.ms', value: 13.0513)
    @backend.collect_metric(m)
    assert_equal [-1, 1, 7, "mock.ms", "ms", -2, A_TIME, 1], @io.string.unpack("sssA7A2sLs")
    assert_in_delta 13.0513, @io.string.unpack("sssA7A2sLsf").last, 0.00001
  end

  def test_store_g
    m = StatsD::Instrument::Metric::new(type: :g, name: 'mock.g', value: 15.0580)
    @backend.collect_metric(m)
    assert_equal [-1, 1, 6, "mock.g", "g", -2, A_TIME, 1], @io.string.unpack("sssA6A2sLs")
    assert_in_delta 15.0580, @io.string.unpack("sssA6A2sLsf").last, 0.00001
  end

  def test_store_counters
    m = StatsD::Instrument::Metric::new(type: :c, name: 'one.c1')
    @backend.collect_metric(m)
    m = StatsD::Instrument::Metric::new(type: :c, name: 'two.c1')
    @backend.collect_metric(m)
    m = StatsD::Instrument::Metric::new(type: :c, name: 'two.c1')
    @backend.collect_metric(m)
    assert_equal [-1, 1, 6, "one.c1", "c", -2, A_TIME, 1, 1, -1, 2, 6, "two.c1", "c", 2, 1, 2, 1],
      @io.string.unpack("sssA6A2sLslsssA6A2slsl")
  end

  def test_file_store
    Dir.mktmpdir do |tmp_dir|
      fb = StatsD::Instrument::Backends::StoreBackend.new(tmp_dir)
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :c, name: 'one.c1'))
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :c, name: 'one.c1', value: 42))
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :c, name: 'one.c2'))
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :c, name: 'one.c1'))
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :ms, name: 'mock.ms', value: 1234))
      fb.collect_metric(StatsD::Instrument::Metric::new(type: :g, name: 'mock.g', value: 56789))
      file = File.join(tmp_dir, Time.now.strftime("%Y-%m-%d"), "#{$$}.statsb")
      assert File.exist?(file)
      fb.reopen
      assert_equal 107, File.size(file)
      File.open(file, 'rb') do |io|
        unpacker = StatsD::Instrument::Backends::Store::Unpacker.new(io)
        assert_equal "one.c1:1|c", unpacker.next_metric
        assert_equal "one.c1:42|c", unpacker.next_metric
        assert_equal "one.c2:1|c", unpacker.next_metric
        assert_equal "one.c1:1|c", unpacker.next_metric
        assert_equal "mock.ms:1234.0|ms", unpacker.next_metric
        assert_equal "mock.g:56789.0|g", unpacker.next_metric
      end
    end
  end
end
