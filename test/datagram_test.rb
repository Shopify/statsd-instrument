# frozen_string_literal: true

require "test_helper"

class DatagramTest < Minitest::Test
  def test_parsing_datagrams
    datagram = "Kernel.Orders.order_creation_path:1|c|" \
      "#order_source:web,code_source:NilController#NilAction,order_builder:false," \
      "multi_currency:false,fulfillment_orders_beta_enabled:false"

    parsed = StatsD::Instrument::Datagram.new(datagram)
    assert_includes(parsed.tags, "code_source:NilController#NilAction")
  end
end
