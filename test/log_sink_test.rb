# frozen_string_literal: true

require "test_helper"

class LogSinkTest < Minitest::Test
  def test_log_sink
    logger = Logger.new(log = StringIO.new)
    logger.formatter = proc do |severity, _datetime, _progname, msg|
      "#{severity}: #{msg}\n"
    end

    log_sink = StatsD::Instrument::LogSink.new(logger)
    log_sink << "foo:1|c" << "bar:1|c"

    assert_equal(<<~LOG, log.string)
      DEBUG: [StatsD] foo:1|c
      DEBUG: [StatsD] bar:1|c
    LOG
  end

  def test_log_sink_chomps_trailing_newlines
    logger = Logger.new(log = StringIO.new)
    logger.formatter = proc do |severity, _datetime, _progname, msg|
      "#{severity}: #{msg}\n"
    end

    log_sink = StatsD::Instrument::LogSink.new(logger)
    log_sink << "foo:1|c\n" << "bar:1|c\n"

    assert_equal(<<~LOG, log.string)
      DEBUG: [StatsD] foo:1|c
      DEBUG: [StatsD] bar:1|c
    LOG
  end
end
