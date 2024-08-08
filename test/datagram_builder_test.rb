# frozen_string_literal: true

require "test_helper"

class DatagramBuilderTest < Minitest::Test
  def setup
    @datagram_builder = StatsD::Instrument::DatagramBuilder.new
  end

  def test_normalize_name
    assert_equal("foo", @datagram_builder.send(:normalize_name, "foo"))
    assert_equal("fo_o", @datagram_builder.send(:normalize_name, "fo|o"))
    assert_equal("fo_o", @datagram_builder.send(:normalize_name, "fo@o"))
    assert_equal("fo_o", @datagram_builder.send(:normalize_name, "fo:o"))
  end

  def test_compile_unsupported_tag_names
    assert_equal("ign#ored", @datagram_builder.send(:compile_tags, ["ign#o|re,d"]))
    # NOTE: how this is interpreted by the backend is undefined.
    # We rely on the user to not do stuff like this if they don't want to be surprised.
    # We do not want to take the performance hit of normalizing this.
    assert_equal("lol::class:omg::lol", @datagram_builder.send(:compile_tags, { "lol::class" => "omg::lol" }))
  end

  def test_compile_tags_converts_hash_to_array
    assert_equal("tag:value", @datagram_builder.send(:compile_tags, { tag: "value" }))
    assert_equal("tag1:v1,tag2:v2", @datagram_builder.send(:compile_tags, { tag1: "v1", tag2: "v2" }))
  end

  def test_c
    datagram = @datagram_builder.c("foo", 1, nil, nil)
    assert_equal("foo:1|c", datagram)

    datagram = @datagram_builder.c("fo:o", 10, 0.1, nil)
    assert_equal("fo_o:10|c|@0.1", datagram)
  end

  def test_ms
    datagram = @datagram_builder.ms("foo", 1, nil, nil)
    assert_equal("foo:1|ms", datagram)

    datagram = @datagram_builder.ms("fo:o", 10, 0.1, nil)
    assert_equal("fo_o:10|ms|@0.1", datagram)
  end

  def test_g
    datagram = @datagram_builder.g("foo", 1, nil, nil)
    assert_equal("foo:1|g", datagram)

    datagram = @datagram_builder.g("fo|o", 10, 0.01, nil)
    assert_equal("fo_o:10|g|@0.01", datagram)
  end

  def test_s
    datagram = @datagram_builder.s("foo", 1, nil, nil)
    assert_equal("foo:1|s", datagram)

    datagram = @datagram_builder.s("fo@o", 10, 0.01, nil)
    assert_equal("fo_o:10|s|@0.01", datagram)
  end

  def test_h
    datagram = @datagram_builder.h("foo", 1, nil, nil)
    assert_equal("foo:1|h", datagram)

    datagram = @datagram_builder.h("fo@o", 10, 0.01, nil)
    assert_equal("fo_o:10|h|@0.01", datagram)
  end

  def test_d
    datagram = @datagram_builder.d("foo", 1, nil, nil)
    assert_equal("foo:1|d", datagram)

    datagram = @datagram_builder.d("fo@o", 10, 0.01, nil)
    assert_equal("fo_o:10|d|@0.01", datagram)
  end

  def test_tags
    datagram = @datagram_builder.d("foo", 10, nil, {})
    assert_equal("foo:10|d", datagram)

    datagram = @datagram_builder.d("foo", 10, nil, [])
    assert_equal("foo:10|d", datagram)

    datagram = @datagram_builder.d("foo", 10, nil, ["foo", "bar"])
    assert_equal("foo:10|d|#foo,bar", datagram)

    datagram = @datagram_builder.d("foo", 10, 0.1, ["foo:bar"])
    assert_equal("foo:10|d|@0.1|#foo:bar", datagram)

    datagram = @datagram_builder.d("foo", 10, 1, foo: "bar", baz: "quc")
    assert_equal("foo:10|d|#foo:bar,baz:quc", datagram)
  end

  def test_prefix
    datagram_builder = StatsD::Instrument::DatagramBuilder.new(prefix: "foo")
    datagram = datagram_builder.c("bar", 1, nil, nil)
    assert_equal("foo.bar:1|c", datagram)

    # The prefix should also be normalized
    datagram_builder = StatsD::Instrument::DatagramBuilder.new(prefix: "foo|bar")
    datagram = datagram_builder.c("baz", 1, nil, nil)
    assert_equal("foo_bar.baz:1|c", datagram)
  end

  def test_default_tags
    datagram_builder = StatsD::Instrument::DatagramBuilder.new(default_tags: ["foo"])
    datagram = datagram_builder.c("bar", 1, nil, nil)
    assert_equal("bar:1|c|#foo", datagram)

    datagram = datagram_builder.c("bar", 1, nil, a: "b")
    assert_equal("bar:1|c|#foo,a:b", datagram)

    # We do not filter out duplicates, because detecting dupes is too time consuming.
    # We let the server deal with the situation
    datagram = datagram_builder.c("bar", 1, nil, ["foo"])
    assert_equal("bar:1|c|#foo,foo", datagram)

    # Default tags are also normalized
    datagram_builder = StatsD::Instrument::DatagramBuilder.new(default_tags: ["f,o|o"])
    datagram = datagram_builder.c("bar", 1, nil, nil)
    assert_equal("bar:1|c|#foo", datagram)
  end

  def test_timing_with_multiple_values
    dt = @datagram_builder.timing_value_packed("test_distribution", "d", [0, 3, 6, 9, 12, 15, 18, 21, 24, 27], 1, nil)
    assert_equal("test_distribution:0:3:6:9:12:15:18:21:24:27|d", dt)
  end
end
