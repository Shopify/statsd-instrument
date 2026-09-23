# frozen_string_literal: true

module StatsD
  module Instrument
    # @note This class is part of the new Client implementation that is intended
    #   to become the new default in the next major release of this library.
    class DatagramBuilder
      extend Forwardable
      class << self
        def unsupported_datagram_types(*types)
          types.each do |type|
            define_method(type) do |_, _, _, _|
              raise NotImplementedError, "Type #{type} metrics are not supported by #{self.class.name}."
            end
          end
        end

        def datagram_class
          StatsD::Instrument::Datagram
        end

        def normalize_string(string)
          string = string.tr("|#\r\n", "_") if /[|#\r\n]/.match?(string)
          string
        end
      end

      def initialize(prefix: nil, default_tags: nil)
        @prefix = prefix.nil? ? "" : "#{Sanitization.name(prefix.to_s)}."
        @default_tags = default_tags.nil? || default_tags.empty? ? nil : compile_tags(default_tags, "|#".b)
      end

      def c(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "c", sample_rate, tags)
      end

      def g(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "g", sample_rate, tags)
      end

      def ms(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "ms", sample_rate, tags)
      end

      def s(name, value, sample_rate, tags)
        value = value.to_s
        value = value.tr("\r\n", "_") if /[\r\n]/.match?(value)
        generate_generic_datagram(name, value, "s", sample_rate, tags)
      end

      def h(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "h", sample_rate, tags)
      end

      def d(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "d", sample_rate, tags)
      end

      def timing_value_packed(name, type, values, sample_rate, tags)
        # here values is an array
        values = values.join(":")
        generate_generic_datagram(name, values, type, sample_rate, tags)
      end

      def kv(name, value, sample_rate, tags)
        generate_generic_datagram(name, value, "kv", sample_rate, tags)
      end

      def latency_metric_type
        :ms
      end

      def normalize_tags(tags, buffer = "".b)
        compile_tags(tags, buffer)
      end

      protected

      # Utility function to remove invalid characters from a StatsD metric name
      def normalize_name(name)
        Sanitization.name(name)
      end

      def generate_generic_datagram(name, value, type, sample_rate, tags)
        datagram = "".b <<
          @prefix <<
          (Sanitization::NAME_PATTERN.match?(name) ? name.tr(Sanitization::NAME_CHARACTERS, "_") : name) <<
          ":" << value.to_s <<
          "|" << type

        datagram << "|@" << sample_rate.to_s if sample_rate && sample_rate < 1

        unless @default_tags.nil?
          datagram << @default_tags
        end

        unless tags.nil? || tags.empty?
          datagram << (@default_tags.nil? ? "|#" : ",")
          compile_tags(tags, datagram)
        end

        datagram
      end

      def compile_tags(tags, buffer = "".b)
        if tags.is_a?(String)
          # String tags are already serialized: commas separate tags here.
          tags = self.class.normalize_string(tags) if Sanitization::TAG_PATTERN.match?(tags)
          buffer << tags
          return buffer
        end
        if tags.is_a?(Hash)
          first = true
          tags.each do |key, value|
            if first
              first = false
            else
              buffer << ","
            end
            key = key.to_s
            key = key.tr(Sanitization::TAG_CHARACTERS, "") if Sanitization::TAG_PATTERN.match?(key)
            value = value.to_s
            value = value.tr(Sanitization::TAG_CHARACTERS, "") if Sanitization::TAG_PATTERN.match?(value)
            buffer << key << ":" << value
          end
        else
          if tags.any? { |tag| Sanitization::TAG_PATTERN.match?(tag) }
            tags = tags.map { |tag| Sanitization.tag(tag) }
          end
          buffer << tags.join(",")
        end
        buffer
      end
    end
  end
end
