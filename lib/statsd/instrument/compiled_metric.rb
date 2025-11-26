# frozen_string_literal: true

module StatsD
  module Instrument
    # A compiled metric pre-builds the datagram template at definition time
    # to minimize allocations during metric emission. This is particularly
    # beneficial for high-frequency metrics with consistent tag patterns.
    #
    # Example:
    #   CheckoutMetric = StatsD::Instrument::CompiledMetric::Counter.define(
    #     name: "checkout.completed",
    #     static_tags: { service: "web" },
    #     tags: { shop_id: Integer, user_id: Integer }
    #   )
    #
    #   # Later, emit with minimal allocations:
    #   CheckoutMetric.increment(shop_id: 123, user_id: 456, value: 1)
    class CompiledMetric
      # Maximum number of unique tag combinations to cache before clearing
      # the cache to prevent unbounded memory growth
      MAX_TAG_COMBINATION_CACHE_SIZE = 5000
      private_constant(:MAX_TAG_COMBINATION_CACHE_SIZE)

      class << self
        # Defines a new compiled metric class with the given configuration.
        #
        # @param name [String] The metric name
        # @param static_tags [Hash{Symbol, String => String, Integer, Float}] Tags with fixed values
        # @param tags [Hash{Symbol, String => Class}] Tags with dynamic values (Integer, Float, or String)
        # @param no_prefix [Boolean] If true, skip the StatsD prefix
        # @return [Class] A new CompiledMetric subclass configured for this metric
        def define(name:, static_tags: {}, tags: {}, no_prefix: false)
          # Build the tag template string
          tags_str =
            tags.map do |(k, v)|
              tag_name = normalize_tag_name(k)
              placeholder =
                if v == String
                  "%s"
                elsif v == Integer
                  "%d"
                elsif v == Float
                  "%f"
                else
                  raise ArgumentError, "Unsupported tag value type: #{v}. Use String, Integer, or Float class."
                end
              "#{tag_name}:#{placeholder}"
            end

          static_tags_str =
            static_tags.map do |(k, v)|
              tag_name = normalize_tag_name(k)
              value = normalize_tag_value(v)
              "#{tag_name}:#{value}"
            end

          all_tags = (static_tags_str + tags_str).join(",")

          # Create a new class for this specific metric
          # Using classes instead of instances for better YJIT optimization
          metric_class = Class.new(self) do
            @name = normalize_name(name)
            @type = type
            @prefix =
              if !no_prefix && StatsD.singleton_client.prefix
                StatsD.singleton_client.prefix + "_"
              end

            # Build the datagram blueprint with sprintf placeholders
            # Format: "<prefix><name>:%d|<type>|#<tags>"
            @datagram_blueprint = "#{@prefix}#{@name}:%d|#{@type}"
            unless all_tags.empty?
              @datagram_blueprint << "|##{all_tags}"
            end

            @tag_combination_cache = {}
            @singleton_client = StatsD.singleton_client

            if tags.any?
              define_dynamic_increment_method(tags)
            else
              define_static_increment_method
            end
          end

          metric_class
        end

        # Normalizes tag names by removing StatsD protocol special characters
        # @param name [Symbol, String] The tag name
        # @return [String] The normalized tag name
        def normalize_tag_name(name)
          name = name.to_s
          name = name.tr("|,", "") if /[|,]/.match?(name)
          name
        end

        # Normalizes tag values by removing StatsD protocol special characters
        # @param value [String, Integer, Float] The tag value
        # @return [String] The normalized tag value
        def normalize_tag_value(value)
          value = value.to_s
          value = value.tr("|,", "") if /[|,]/.match?(value)
          value
        end

        # @return [String] The metric type character (e.g., "c" for counter)
        def type
          raise NotImplementedError, "Subclasses must implement #type"
        end

        private

        # Normalizes metric names by replacing special characters
        # @param name [String] The metric name
        # @return [String] The normalized metric name
        def normalize_name(name)
          name.tr(":|@", "_")
        end

        # Defines the increment method for metrics with dynamic tags
        # Generates optimized code with tag caching
        def define_dynamic_increment_method(tags)
          arg_names = tags.map.with_index { |(k, _v), i| "arg#{i}" }

          increment_code = <<~RUBY
            def self.increment(#{arg_names.join(", ")}, value: 1)
              # Compute hash of tag values for cache lookup
              cache_key = #{arg_names.map { |arg| "#{arg}.hash" }.join(" ^ ")}

              # Look up or create a PrecompiledDatagram
              datagram =
                if (cache = @tag_combination_cache)
                  cache[cache_key] ||=
                    begin
                      datagram = PrecompiledDatagram.new([#{arg_names.join(", ")}], @datagram_blueprint, @type)

                      # Clear cache if it grows too large to prevent memory bloat
                      if cache.size > MAX_TAG_COMBINATION_CACHE_SIZE
                        @tag_combination_cache = nil
                      end

                      datagram
                    end

                  # Hash collision detection
                  if datagram && #{arg_names.map.with_index { |arg, i| "#{arg} != datagram.tag_values[#{i}]" }.join(" || ")}
                    # Hash collision - fall back to creating a new datagram
                    datagram = nil
                  end

                  datagram
                else
                  # Cache was cleared, create datagram without caching
                  nil
                end

              datagram ||= PrecompiledDatagram.new([#{arg_names.join(", ")}], @datagram_blueprint, @type)

              @singleton_client.emit_precompiled_metric(datagram, value)
            end
          RUBY

          instance_eval(increment_code, __FILE__, __LINE__ + 1)
        end

        # Defines the increment method for metrics without dynamic tags
        # Uses a single precompiled datagram for all calls
        def define_static_increment_method
          @static_datagram = PrecompiledDatagram.new([], @datagram_blueprint, @type)

          instance_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            def self.increment(value: 1)
              @singleton_client.emit_precompiled_metric(@static_datagram, value)
            end
          RUBY
        end
      end

      # A precompiled datagram that can quickly build the final StatsD datagram
      # string using sprintf formatting with cached tag values.
      class PrecompiledDatagram
        attr_reader :tag_values, :datagram_blueprint, :metric_type

        # @param tag_values [Array] The tag values to cache
        # @param datagram_blueprint [String] The sprintf template
        # @param metric_type [String] The metric type character (e.g., "c")
        def initialize(tag_values, datagram_blueprint, metric_type)
          @tag_values = tag_values
          @datagram_blueprint = datagram_blueprint
          @metric_type = metric_type
          @hash_code = [@datagram_blueprint, @tag_values].hash
        end

        # Enables PrecompiledDatagram to be used as a hash key for aggregation
        def hash
          @hash_code
        end

        # Enables PrecompiledDatagram to be used as a hash key for aggregation
        def eql?(other)
          other.is_a?(PrecompiledDatagram) &&
            @datagram_blueprint == other.datagram_blueprint &&
            @tag_values == other.tag_values
        end

        # Builds the final datagram string by substituting values into the blueprint
        # @param value [Numeric] The metric value
        # @return [String] The complete StatsD datagram
        def to_datagram(value)
          # Sanitize and convert tag values to strings
          values = @tag_values.map do |arg|
            case arg
            when String
              # Remove StatsD protocol delimiters if present
              if /[|,]/.match?(arg)
                arg.tr("|,", "")
              else
                arg
              end
            when Integer, Float
              arg.to_s
            end
          end

          # Prepend the metric value
          values.unshift(value)

          # Use sprintf to build the final datagram
          @datagram_blueprint % values
        end
      end

      # Counter metric type
      class Counter < CompiledMetric
        class << self
          def type
            "c"
          end
        end
      end
    end
  end
end
