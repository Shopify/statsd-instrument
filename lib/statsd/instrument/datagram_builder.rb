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
          string = string.tr("|#", "_") if /[|#]/.match?(string)
          string
        end
      end

      def initialize(prefix: nil, default_tags: nil)
        @prefix = prefix.nil? ? "" : "#{prefix}.".tr(":|@", "_")
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
        # Fast path when no normalization is needed to avoid copying the string
        return name unless /[:|@]/.match?(name)

        name.tr(":|@", "_")
      end

      def generate_generic_datagram(name, value, type, sample_rate, tags)
        datagram = "".b <<
          @prefix <<
          (/[:|@]/.match?(name) ? name.tr(":|@", "_") : name) <<
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
          tags = self.class.normalize_string(tags) if /[|,]/.match?(tags)
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
            key = key.tr("|,", "") if /[|,]/.match?(key)
            value = value.to_s
            value = value.tr("|,", "") if /[|,]/.match?(value)
            buffer << key << ":" << value
          end
        else
          if tags.any? { |tag| /[|,]/.match?(tag) }
            tags = tags.map { |tag| tag.tr("|,", "") }
          end
          buffer << tags.join(",")
        end
        buffer
      end
    end
  end
end
