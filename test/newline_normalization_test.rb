# frozen_string_literal: true

require "test_helper"

class NewlineNormalizationTest < Minitest::Test
  def setup
    @old_client = StatsD.singleton_client
    @sink = StatsD::Instrument::CaptureSink.new(parent: StatsD::Instrument::NullSink.new)
    @clients = []
  end

  def teardown
    StatsD.singleton_client = @old_client
    @clients.each do |client|
      aggregator = client.instance_variable_get(:@aggregator)
      next unless aggregator

      aggregator.instance_variable_get(:@flush_thread)&.kill
      ObjectSpace.undefine_finalizer(aggregator)
    end
  end

  def test_all_generic_metric_types_keep_line_breaks_inside_the_prefix
    builder = StatsD::Instrument::DatagramBuilder.new(prefix: "storefront")
    [:c, :g, :ms, :s, :h, :d, :kv].each do |type|
      ["\n", "\r", "\r\n"].each do |delimiter|
        datagram = builder.public_send(type, "http.requests#{delimiter}checkout", 1, nil, nil)
        assert_equal("storefront.http.requests#{"_" * delimiter.size}checkout:1|#{type}", datagram)
      end
    end
  end

  def test_prefix_and_name_are_sanitized_without_mutating_inputs
    prefix = "app\r\nnamespace"
    name = "name\r\nchild"
    builder = StatsD::Instrument::DatagramBuilder.new(prefix: prefix)
    assert_equal("app__namespace.name__child:1|c", builder.c(name, 1, nil, nil))
    assert_equal("app\r\nnamespace", prefix)
    assert_equal("name\r\nchild", name)
    assert_equal("name__child", builder.send(:normalize_name, name))
  end

  def test_array_and_hash_tags_remove_delimiters_without_mutating_inputs
    builder = StatsD::Instrument::DatagramBuilder.new
    array = ["k\r\ney:v\r\na|l,ue", "good:tag"].freeze
    hash = { "k\r\ney" => "v\r\na|l,ue", good: "tag" }.freeze
    [array, hash].each do |tags|
      assert_equal("name:1|c|#key:value,good:tag", builder.c("name", 1, nil, tags))
    end
    assert_equal("k\r\ney:v\r\na|l,ue", array.first)
    assert_equal("v\r\na|l,ue", hash.values.first)
  end

  def test_serialized_tags_preserve_commas_as_separators
    builder = StatsD::Instrument::DatagramBuilder.new
    assert_equal("name:1|c|#a:one_,b:two_", builder.c("name", 1, nil, "a:one\r,b:two\n"))
    assert_equal("name:1|c|#a:one,b:two", builder.c("name", 1, nil, "a:one,b:two"))
  end

  def test_default_tags_in_each_supported_representation
    [["k:v\n"], { k: "v\n" }, "k:v\n"].each do |tags|
      builder = StatsD::Instrument::DatagramBuilder.new(default_tags: tags)
      datagram = builder.c("name", 1, nil, ["extra:tag"])
      refute_match(/[\r\n]/, datagram)
      assert_includes(datagram, ",extra:tag")
    end
  end

  def test_set_values_replace_newlines
    builder = StatsD::Instrument::DatagramBuilder.new(prefix: "app")
    assert_equal("app.users:alice__smith|s", builder.s("users", "alice\r\nsmith", nil, nil))
    assert_equal("app.users:42|s", builder.s("users", 42, nil, nil))
  end

  def test_unicode_and_valid_inputs_are_unchanged
    builder = StatsD::Instrument::DatagramBuilder.new(prefix: "shop")
    assert_equal("shop.café:1|c|#city:東京", builder.c("café", 1, nil, ["city:東京"]))
    name = +"safe.name"
    assert_same(name, builder.send(:normalize_name, name))
  end

  def test_dogstatsd_service_check_name_and_tags
    builder = StatsD::Instrument::DogStatsDDatagramBuilder.new(prefix: "app\n")
    assert_equal("_sc|app_.service_check|0|#key:value", builder._sc("service\rcheck", :ok, tags: ["key:va\nlue"]))
    # Event text has its own documented escaping; tag normalization must preserve it.
    event = builder._e("title", "first\nsecond", tags: ["key:va\nlue"])
    refute_match(/[\r\n]/, event)
    assert_includes(event, 'first\nsecond')
    assert_includes(event, "|#key:value")
  end

  def test_normal_and_aggregated_client_paths
    [false, true].each do |aggregate|
      client = new_client(aggregate)
      [:increment, :gauge, :measure, :distribution, :histogram].each do |method|
        client.public_send(method, "metric\r\nname", 1, tags: { "k\r\ney" => "va\nlue" })
        client.public_send(method, "unprefixed\nname", 1, tags: ["key:va\nlue"], no_prefix: true)
      end
      client.set("set\nname", "v\nalue", tags: ["key:va\nlue"])
      client.force_flush
      assert_equal(11, @sink.datagrams.size)
      @sink.datagrams.each do |datagram|
        refute_match(/[\r\n]/, datagram.source)
        assert_includes(datagram.source, "key:value")
      end
      @sink.clear
    end
  end

  def test_aggregator_finalizer_and_unhealthy_thread_fallback
    client = new_client(true)
    aggregator = client.instance_variable_get(:@aggregator)
    client.increment("name\nchild", tags: ["key:va\nlue"])
    finalizer = aggregator.instance_variable_get(:@finalizer)
    StatsD::Instrument::Aggregator.finalize(finalizer).call
    assert_equal(1, @sink.datagrams.size)
    refute_match(/[\r\n]/, @sink.datagrams.first.source)

    @sink.clear
    aggregator.stubs(:thread_healthcheck).returns(false)
    client.increment("name\nchild", tags: ["key:va\nlue"])
    assert_equal(1, @sink.datagrams.size)
    refute_match(/[\r\n]/, @sink.datagrams.first.source)
  end

  def test_compiled_static_and_dynamic_fields_with_and_without_aggregation
    [false, true].each do |aggregate|
      client = new_client(aggregate)
      StatsD.singleton_client = client
      [
        StatsD::Instrument::CompiledMetric::Counter,
        StatsD::Instrument::CompiledMetric::Gauge,
        StatsD::Instrument::CompiledMetric::Distribution,
      ].each do |base|
        metric = Class.new(base) do
          define(name: "name\r\nchild", static_tags: { "static\nkey" => "va\rlue" }, tags: { dynamic: String, symbol: Symbol })
        end
        2.times { metric.public_send(base.method_name, 1, dynamic: "va\nlue", symbol: :"sym\rbol") }
        client.force_flush
        assert_equal(aggregate ? 1 : 2, @sink.datagrams.size)
        @sink.datagrams.each do |datagram|
          refute_match(/[\r\n]/, datagram.source)
          assert_includes(datagram.source, "app_.name__child:")
          assert_includes(datagram.source, "statickey:value")
          assert_includes(datagram.source, "dynamic:value,symbol:symbol")
        end
        @sink.clear

        metric = Class.new(base) { define(name: "static\nname", static_tags: { key: "va\nlue" }) }
        metric.public_send(base.method_name, 1)
        client.force_flush
        assert_equal(1, @sink.datagrams.size)
        refute_match(/[\r\n]/, @sink.datagrams.first.source)
        @sink.clear
      end
    end
  end

  def test_compiled_default_tags_and_dynamic_keys
    builder = StatsD::Instrument::CompiledMetric::DatagramBlueprintBuilder
    [["default:va\nlue"], { default: "va\nlue" }, "default:va\nlue"].each do |tags|
      blueprint = builder.build(
        name: "name\n",
        type: "c",
        client_prefix: "app\r",
        no_prefix: false,
        default_tags: tags,
        static_tags: {},
        dynamic_tags: { "dy\nnamic" => String },
        sample_rate: 1,
      )
      datagram = StatsD::Instrument::CompiledMetric::PrecompiledDatagram.new(["va\nlue"], blueprint, 1).to_datagram(1)
      assert_equal("app_.name_:1|c|#default:value,dynamic:value", datagram)
    end
  end

  def test_compiled_dynamic_tags_are_checked_after_mutation_and_with_cache_disabled
    StatsD.singleton_client = new_client(false)
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter) do
      define(name: "name", tags: { key: String }, max_cache_size: 0)
    end
    tag = +"value"
    metric.increment(key: tag)
    @sink.clear
    tag << "\nwith|newline"
    metric.increment(key: tag)
    assert_equal(1, @sink.datagrams.size)
    refute_match(/[\r\n]/, @sink.datagrams.first.source)
    assert_includes(@sink.datagrams.first.source, "|#default:value,key:valuewithnewline")
  end

  def test_compiled_name_does_not_freeze_the_input_string
    StatsD.singleton_client = new_client(false)
    name = +"name"
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter)
    metric.define(name: name)
    name << ".changed"
    assert_equal("name", metric.metric_name)
    assert_predicate(metric.metric_name, :frozen?)
  end

  def test_normalization_is_silent
    StatsD.logger.expects(:warn).never
    StatsD.logger.expects(:error).never
    client = new_client(false)
    client.increment("name\n", tags: ["key:va\nlue"])
    assert_equal(1, @sink.datagrams.size)
    assert_equal("app_.name_:1|c|#default:value,key:value", @sink.datagrams.first.source)
  end

  def test_names_and_prefixes_share_normalization_across_all_paths
    [false, true].each do |aggregate|
      [" ", "\t", "\n", "\r", "\f", "\v", ":", "|", "@"].each do |character|
        client = new_client(aggregate).clone_with_options(prefix: "app#{character}prefix")
        @clients << client
        StatsD.singleton_client = client
        client.increment("my#{character}value")
        client.increment("my#{character}value", no_prefix: true)
        metric = Class.new(StatsD::Instrument::CompiledMetric::Counter)
        metric.define(name: "my#{character}value")
        metric.increment
        unprefixed = Class.new(StatsD::Instrument::CompiledMetric::Counter)
        unprefixed.define(name: "my#{character}value", no_prefix: true)
        unprefixed.increment
        client.force_flush
        assert_equal(4, @sink.datagrams.size)
        assert_equal(["app_prefix.my_value", "app_prefix.my_value", "my_value", "my_value"], @sink.datagrams.map(&:name).sort)
        assert_equal("my_value", metric.metric_name)
        @sink.clear
      end
    end
  end

  def test_tag_values_and_service_check_messages_keep_spaces
    builder = StatsD::Instrument::DogStatsDDatagramBuilder.new(prefix: "my app")
    assert_equal("my_app.my_metric:1|c|#key:hello world", builder.c("my metric", 1, nil, ["key:hello world"]))
    assert_equal("my_app.my_metric:1|c|#key:hello world", builder.c("my metric", 1, nil, { key: "hello world" }))
    assert_equal("my_app.users:Alice Smith|s", builder.s("users", "Alice Smith", nil, nil))
    assert_equal("_sc|my_app.my_service|0|m:hello world_", builder._sc("my service", :ok, message: "hello world\n"))

    StatsD.singleton_client = new_client(false)
    metric = Class.new(StatsD::Instrument::CompiledMetric::Counter)
    metric.define(name: "my metric", static_tags: { static: "hello world" }, tags: { dynamic: String })
    metric.increment(dynamic: "hello world")
    assert_includes(@sink.datagrams.last.tags, "static:hello world")
    assert_includes(@sink.datagrams.last.tags, "dynamic:hello world")
  end

  private

  def new_client(aggregate)
    client = StatsD::Instrument::Client.new(
      sink: @sink,
      prefix: "app\n",
      default_tags: ["default:va\nlue"],
      enable_aggregation: aggregate,
      aggregation_flush_interval: 3600,
    )
    @clients << client
    client
  end
end
