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
      # Default maximum number of unique tag combinations to cache before clearing
      # the cache to prevent unbounded memory growth
      DEFAULT_MAX_TAG_COMBINATION_CACHE_SIZE = 5000

      class << self
        # Defines a new compiled metric class with the given configuration.
        #
        # @param name [String] The metric name
        # @param static_tags [Hash{Symbol, String => String, Integer, Float}] Tags with fixed values
        # @param tags [Hash{Symbol, String => Class}] Tags with dynamic values (Integer, Float, or String)
        # @param no_prefix [Boolean] If true, skip the StatsD prefix and default_tags
        # @param max_cache_size [Integer] Maximum tag combinations to cache before clearing
        # @return [Class] A new CompiledMetric subclass configured for this metric
        def define(name:, static_tags: {}, tags: {}, no_prefix: false, max_cache_size: DEFAULT_MAX_TAG_COMBINATION_CACHE_SIZE)
          client = StatsD.singleton_client

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

          # Add default_tags from client unless no_prefix is true
          default_tags_str = []
          unless no_prefix
            default_tags_str = (client.default_tags || []).map do |tag|
              normalize_tag_value(tag)
            end
          end

          all_tags = (default_tags_str + static_tags_str + tags_str).join(",")

          # Create a new class for this specific metric
          # Using classes instead of instances for better YJIT optimization
          metric_class = Class.new(self) do
            @name = normalize_name(name)
            @type = type

            # Build prefix: only add it if no_prefix is false AND a prefix exists
            @prefix = ""
            if !no_prefix && client.prefix
              @prefix = client.prefix + "_"
            end

            # Build the datagram blueprint with sprintf placeholders
            # Format: "<prefix><name>:%d|<type>|#<tags>"
            @datagram_blueprint = if all_tags.empty?
              "#{@prefix}#{@name}:%d|#{@type}"
            else
              "#{@prefix}#{@name}:%d|#{@type}|##{all_tags}"
            end

            @tag_combination_cache = {}
            @max_cache_size = max_cache_size
            @singleton_client = client

            define_metric_method(tags)
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

        # @return [Symbol] The method name to define (e.g., :increment)
        def method_name
          raise NotImplementedError, "Subclasses must implement #method_name"
        end

        # @return [Numeric, nil] The default value for the metric
        def default_value
          raise NotImplementedError, "Subclasses must implement #default_value"
        end

        # @return [Boolean] Whether the metric method accepts a block
        def accepts_block?
          false
        end

        # Defines the metric emission method - must be implemented by subclasses
        # @param tags [Hash] The dynamic tags configuration
        def define_metric_method(tags)
          if tags.any?
            define_dynamic_method(tags)
          else
            define_static_method
          end
        end

        private

        # Defines the metric method for metrics with dynamic tags
        # Generates optimized code with tag caching
        def define_dynamic_method(tags)
          # Use the actual tag names as keyword arguments
          tag_names = tags.keys
          method = method_name
          default_val = default_value
          block_param = accepts_block? ? ", &block" : ""

          method_code = <<~RUBY
            def self.#{method}(#{tag_names.map { |name| "#{name}:" }.join(", ")}, value: #{default_val.inspect}, sample_rate: nil#{block_param})
              # Compute hash of tag values for cache lookup
              cache_key = #{tag_names.map { |name| "#{name}.hash" }.join(" ^ ")}

              # Look up or create a PrecompiledDatagram
              datagram =
                if (cache = @tag_combination_cache)
                  cached_datagram = cache[cache_key] ||=
                    begin
                      new_datagram = PrecompiledDatagram.new([#{tag_names.join(", ")}], @datagram_blueprint)

                      # Clear cache if it grows too large to prevent memory bloat
                      if cache.size > @max_cache_size
                        @tag_combination_cache = nil
                      end

                      new_datagram
                    end

                  # Hash collision detection
                  if cached_datagram && #{tag_names.map.with_index { |name, i| "#{name} != cached_datagram.tag_values[#{i}]" }.join(" || ")}
                    # Hash collision - fall back to creating a new datagram
                    cached_datagram = nil
                  end

                  cached_datagram
                else
                  # Cache was cleared, create datagram without caching
                  nil
                end

              datagram ||= PrecompiledDatagram.new([#{tag_names.join(", ")}], @datagram_blueprint)

              @singleton_client.emit_precompiled_metric(datagram, value, sample_rate: sample_rate)
            end
          RUBY

          instance_eval(method_code, __FILE__, __LINE__ + 1)
        end

        # Defines the metric method for metrics without dynamic tags
        # Uses a single precompiled datagram for all calls
        def define_static_method
          @static_datagram = PrecompiledDatagram.new([], @datagram_blueprint)
          method = method_name
          default_val = default_value
          block_param = accepts_block? ? ", &block" : ""

          instance_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            def self.#{method}(value: #{default_val.inspect}, sample_rate: nil#{block_param})
              @singleton_client.emit_precompiled_metric(@static_datagram, value, sample_rate: sample_rate)
            end
          RUBY
        end

        # Normalizes metric names by replacing special characters
        # @param name [String] The metric name
        # @return [String] The normalized metric name
        def normalize_name(name)
          name.tr(":|@", "_")
        end
      end

      # A precompiled datagram that can quickly build the final StatsD datagram
      # string using sprintf formatting with cached tag values.
      class PrecompiledDatagram
        attr_reader :tag_values, :datagram_blueprint

        # @param tag_values [Array] The tag values to cache
        # @param datagram_blueprint [String] The sprintf template
        def initialize(tag_values, datagram_blueprint)
          @tag_values = tag_values
          @datagram_blueprint = datagram_blueprint
        end

        # Use object identity for hash key - each unique tag combination
        # gets its own cached PrecompiledDatagram object
        def eql?(other)
          equal?(other)
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

          def method_name
            :increment
          end

          def default_value
            1
          end
        end
      end
    end
  end
end
