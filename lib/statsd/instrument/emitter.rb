# frozen_string_literal: true

module StatsD
  module Instrument
    class Emitter
      attr_accessor :sink

      def initialize(sink:, datagram_builder_class:, prefix:, default_tags:)
        @sink = sink
        @datagram_builder_class = datagram_builder_class
        @prefix = prefix
        @default_tags = default_tags
        @datagram_builder = {}
      end

      def sample?(sample_rate)
        @sink.sample?(sample_rate)
      end

      def serialize_metric(
        type,
        no_prefix,
        name_or_title,
        value_or_status_or_text,
        tags,
        sample_rate,
        extra
      )
        case type
        when :c
          datagram_builder(no_prefix: no_prefix).c(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :g
          datagram_builder(no_prefix: no_prefix).g(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :h
          datagram_builder(no_prefix: no_prefix).h(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :d
          datagram_builder(no_prefix: no_prefix).d(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :ms
          datagram_builder(no_prefix: no_prefix).ms(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :s
          datagram_builder(no_prefix: no_prefix).s(name_or_title, value_or_status_or_text, sample_rate, tags)
        when :sc
          datagram_builder(no_prefix: no_prefix)._sc(
            name_or_title,
            value_or_status_or_text,
            tags:      tags,
            timestamp: extra[0],
            hostname:  extra[1],
            message:   extra[2],
          )
        when :e
          datagram_builder(no_prefix: no_prefix)._e(
            name_or_title,
            value_or_status_or_text,
            tags:             tags,
            timestamp:        extra[0],
            hostname:         extra[1],
            aggregation_key:  extra[2],
            priority:         extra[3],
            source_type_name: extra[4],
            alert_type:       extra[5],
          )
        else
          datagram_builder(no_prefix: no_prefix).send(type, name_or_title, value_or_status_or_text, sample_rate, tags)
        end
      end

      def emit(
        type,
        no_prefix,
        name_or_title,
        value_or_status_or_text,
        tags,
        sample_rate,
        extra
      )
        @sink << serialize_metric(type, no_prefix, name_or_title, value_or_status_or_text, tags, sample_rate, extra)
        StatsD::Instrument::VOID
      end

      def datagram_builder(no_prefix:)
        @datagram_builder[no_prefix] ||= @datagram_builder_class.new(
          prefix: no_prefix ? nil : @prefix,
          default_tags: @default_tags,
        )
      end
    end
  end
end
