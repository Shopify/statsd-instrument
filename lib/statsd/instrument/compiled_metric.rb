# frozen_string_literal: true

module StatsD
  module Instrument
    # A compiled metric pre-builds the datagram template at definition time
    # to minimize allocations during metric emission. This is particularly
    # beneficial for high-frequency metrics with consistent tag patterns.
    #
    # Example:
    #   class CheckoutMetric < StatsD::Instrument::CompiledMetric::Counter
    #     define(
    #       name: "checkout.completed",
    #       static_tags: { service: "web" },
    #       tags: { shop_id: Integer, user_id: Integer }
    #     )
    #   end
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
        # @param sample_rate [Float, nil] The sample rate (0.0-1.0) for this metric, nil for no sampling
        # @param max_cache_size [Integer] Maximum tag combinations this metric supports, and will be retained in-memory. Cardinality beyond this number will fall back to the slow path and should be avoided.
        # @return [Class] A new CompiledMetric subclass configured for this metric
        def define(name:, static_tags: {}, tags: {}, no_prefix: false, sample_rate: nil, max_cache_size: DEFAULT_MAX_TAG_COMBINATION_CACHE_SIZE)
          client = StatsD.singleton_client

          # Build the datagram blueprint using the builder
          # The builder handles prefix, tags compilation, and blueprint construction
          datagram_blueprint = DatagramBlueprintBuilder.build(
            name: name,
            type: type,
            client_prefix: client.prefix,
            no_prefix: no_prefix,
            default_tags: client.default_tags,
            static_tags: static_tags,
            dynamic_tags: tags,
            sample_rate: sample_rate || client.default_sample_rate,
          )

          # Create a new class for this specific metric
          # Using classes instead of instances for better YJIT optimization
          metric_class = tap do
            @name = DatagramBlueprintBuilder.normalize_name(name)
            @datagram_blueprint = datagram_blueprint
            @tag_combination_cache = {}
            @max_cache_size = max_cache_size
            @singleton_client = client
            @sample_rate = sample_rate

            define_metric_method(tags)
          end

          metric_class
        end

        # @return [String] The metric type character (e.g., "c" for counter)
        def type
          raise NotImplementedError, "Subclasses must implement #type"
        end

        # @return [Symbol] The method name to define (e.g., :increment)
        def method_name
          raise NotImplementedError, "Subclasses must implement #method_name"
        end

        # @return [Numeric, nil] The default value for the metric.
        # Returning nil makes __value__ a required argument.
        def default_value
          raise NotImplementedError, "Subclasses must implement #default_value"
        end

        # @return [Boolean] When set to `true`, the created `method_name` method will accept a block.
        # The `value` kwarg will be ignored and instead the execution time of the block in milliseconds will be used.
        # The return value of the block will be passed through.
        def allow_measuring_latency
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

        def sample?(sample_rate)
          @singleton_client.sink.sample?(sample_rate)
        end

        private

        # The placeholder definitions of the metric subclasses will call this method.
        # Once `define` was called during the class creation, it will override the
        # method implementation to emit the actual metric datagrams.
        def require_define_to_be_called
          raise ArgumentError, "Every CompiledMetric subclass needs to call `define` before first invocation of #{method_name}."
        end

        def generate_block_handler
          # For all timing metrics, we have to use the sampling logic.
          # Not doing so would impact performance and CPU usage.
          # See Datadog's documentation for more details: https://github.com/DataDog/datadog-go/blob/20af2dbfabbbe6bd0347780cd57ed931f903f223/statsd/aggregator.go#L281-L283
          <<~RUBY
            __sample_rate__ ||= @sample_rate
            if __sample_rate__ && !sample?(__sample_rate__)
              if block_given?
                return yield
              end

              return StatsD::Instrument::VOID
            end

            if block_given?
              __start__ = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
              begin
                __return_value__ = yield
              ensure
                __stop__ = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
                __value__ = __stop__ - __start__
              end
            end
          RUBY
        end

        # Defines the metric method for metrics with dynamic tags
        # Generates optimized code with tag caching
        def define_dynamic_method(tags)
          # Use the actual tag names as keyword arguments
          tag_names = tags.keys
          method = method_name
          default_val = default_value
          default_val_assignment = default_val.nil? ? "" : " = #{default_val.inspect}"
          allow_block = allow_measuring_latency

          method_code = <<~RUBY
            def self.#{method}(__value__#{default_val_assignment}, #{tag_names.map { |name| "#{name}:" }.join(", ")})
              __return_value__ = StatsD::Instrument::VOID
              #{generate_block_handler if allow_block}

              # Compute hash of tag values for cache lookup
              __cache_key__ = #{tag_names.map { |name| "#{name}.hash" }.join(" ^ ")}

              # Look up or create a PrecompiledDatagram
              __datagram__ =
                if (__cache__ = @tag_combination_cache)
                  __cached_datagram__ = __cache__[__cache_key__] ||=
                    begin
                      __new_datagram__ = PrecompiledDatagram.new([#{tag_names.join(", ")}], @datagram_blueprint, @sample_rate)

                      # Clear cache if it grows too large to prevent memory bloat
                      if __cache__.size >= @max_cache_size
                        StatsD.increment("statsd_instrument.compiled_metric.cache_exceeded_total", tags: { metric_name: @name, max_size: @max_cache_size })
                        @tag_combination_cache = nil
                      end

                      __new_datagram__
                    end

                  # Hash collision detection
                  if #{tag_names.map.with_index { |name, i| "#{name} != __cached_datagram__.tag_values[#{i}]" }.join(" || ")}
                    # Hash collision - fall back to creating a new datagram
                    StatsD.increment("statsd_instrument.compiled_metric.hash_collision_detected", tags: { metric_name: @name })
                    __cached_datagram__ = nil
                  end

                  __cached_datagram__
                end

              __datagram__ ||= PrecompiledDatagram.new([#{tag_names.join(", ")}], @datagram_blueprint, @sample_rate)

              @singleton_client.emit_precompiled_#{method}_metric(__datagram__, __value__)
              __return_value__
            end
          RUBY

          instance_eval(method_code, __FILE__, __LINE__ + 1)
        end

        # Defines the metric method for metrics without dynamic tags
        # Uses a single precompiled datagram for all calls
        def define_static_method
          @static_datagram = PrecompiledDatagram.new([], @datagram_blueprint, @sample_rate)
          method = method_name
          default_val = default_value
          allow_block = allow_measuring_latency

          instance_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            def self.#{method}(__value__ = #{default_val.inspect})
              __return_value__ = StatsD::Instrument::VOID
              #{generate_block_handler if allow_block}
              @singleton_client.emit_precompiled_#{method}_metric(@static_datagram, __value__)
              __return_value__
            end
          RUBY
        end
      end

      # Helper class to build datagram blueprints at definition time.
      # Handles prefix building, tag compilation, and blueprint construction.
      class DatagramBlueprintBuilder
        class << self
          # Builds a datagram blueprint string
          #
          # @param name [String] The metric name
          # @param type [String] The metric type (e.g., "c" for counter)
          # @param client_prefix [String, nil] The client's prefix
          # @param value_format [String] The sprintf format for the value (e.g., "%d", "%f")
          # @param no_prefix [Boolean] Whether to skip the prefix
          # @param default_tags [String, Hash, Array, nil] The client's default tags
          # @param static_tags [Hash] Static tags with fixed values
          # @param dynamic_tags [Hash] Dynamic tags with type specifications
          # @param sample_rate [Float, nil] The sample rate (0.0-1.0), nil for no sampling
          # @param enable_aggregation [Boolean] Whether aggregation is enabled
          # @return [String] The datagram blueprint with sprintf placeholders
          def build(name:, type:, client_prefix:, no_prefix:, default_tags:, static_tags:, dynamic_tags:, sample_rate:)
            # Normalize and build prefix
            normalized_name = normalize_name(name)
            prefix = build_prefix(client_prefix, no_prefix)

            # Compile all tags (default, static, dynamic)
            all_tags = compile_all_tags(default_tags, static_tags, dynamic_tags)

            # Build the datagram blueprint
            # Format: "<prefix><name>:<value_format>|<type>|@<sample_rate>|#<tags>"
            # Note: When aggregation is enabled, sample_rate is applied before aggregation
            if sample_rate && sample_rate < 1
              # Include sample_rate in the blueprint (only when not aggregating)
              if all_tags.empty?
                "#{prefix}#{normalized_name}:%s|#{type}|@#{sample_rate}"
              else
                "#{prefix}#{normalized_name}:%s|#{type}|@#{sample_rate}|##{all_tags}"
              end
            elsif all_tags.empty?
              "#{prefix}#{normalized_name}:%s|#{type}"
            else
              "#{prefix}#{normalized_name}:%s|#{type}|##{all_tags}"
            end
          end

          # Normalizes metric names by replacing special characters
          # @param name [String] The metric name
          # @return [String] The normalized metric name
          def normalize_name(name)
            name.tr(":|@", "_")
          end

          private

          # Builds the metric prefix
          # @param client_prefix [String, nil] The client's prefix
          # @param no_prefix [Boolean] Whether to skip the prefix
          # @return [String] The prefix string (with trailing dot if present)
          def build_prefix(client_prefix, no_prefix)
            return "" if no_prefix || client_prefix.nil?

            "#{client_prefix}."
          end

          # Normalizes tag names/values by removing StatsD protocol special characters
          # @param str [Symbol, String, Integer, Float] The string to normalize
          # @return [String] The normalized string
          def normalize_statsd_string(str)
            str = str.to_s
            str = str.tr("|,", "") if /[|,]/.match?(str)
            str
          end

          # Compiles all tags (default_tags, static_tags, dynamic_tags) into a single string
          # @param default_tags [String, Hash, Array, nil] The client's default tags
          # @param static_tags [Hash] Static tags with fixed values
          # @param dynamic_tags [Hash] Dynamic tags with type specifications
          # @return [String] The comma-separated tags string
          def compile_all_tags(default_tags, static_tags, dynamic_tags)
            default_tags_str = compile_default_tags(default_tags)
            static_tags_str = compile_static_tags(static_tags)
            dynamic_tags_str = compile_dynamic_tags(dynamic_tags)

            (default_tags_str + static_tags_str + dynamic_tags_str).join(",")
          end

          # Compiles default tags from the client (can be String, Hash, or Array)
          # @param default_tags [String, Hash, Array, nil] The client's default tags
          # @return [Array<String>] Array of normalized tag strings
          def compile_default_tags(default_tags)
            return [] if default_tags.nil? || default_tags.empty?

            if default_tags.is_a?(String)
              [normalize_statsd_string(default_tags)]
            elsif default_tags.is_a?(Hash)
              default_tags.map do |key, value|
                "#{normalize_statsd_string(key)}:#{normalize_statsd_string(value)}"
              end
            else
              # Array
              default_tags.map { |tag| normalize_statsd_string(tag) }
            end
          end

          # Compiles static tags (hash of key => value)
          # @param static_tags [Hash] Static tags with fixed values
          # @return [Array<String>] Array of "key:value" strings
          def compile_static_tags(static_tags)
            static_tags.map do |key, value|
              "#{normalize_statsd_string(key)}:#{normalize_statsd_string(value)}"
            end
          end

          # Compiles dynamic tags (hash of key => type) into sprintf placeholders
          # @param dynamic_tags [Hash] Dynamic tags with type specifications
          # @return [Array<String>] Array of "key:%s" placeholder strings
          def compile_dynamic_tags(dynamic_tags)
            dynamic_tags.map do |key, type|
              tag_name = normalize_statsd_string(key)
              unless [String, Integer, Float, Symbol, :Boolean].include?(type)
                raise ArgumentError,
                  "Unsupported tag value type: #{type}. Use String, Integer, Float, Symbol, or :Boolean."
              end
              "#{tag_name}:%s"
            end
          end
        end
      end

      # A precompiled datagram that can quickly build the final StatsD datagram
      # string using sprintf formatting with cached tag values.
      class PrecompiledDatagram
        attr_reader :tag_values, :datagram_blueprint, :sample_rate

        # @param tag_values [Array] The tag values to cache
        # @param datagram_blueprint [String] The sprintf template
        # @param sample_rate [Float] The sample rate (0.0-1.0)
        def initialize(tag_values, datagram_blueprint, sample_rate)
          @tag_values = tag_values
          @datagram_blueprint = datagram_blueprint
          @sample_rate = sample_rate
        end

        # Builds the final datagram string by substituting values into the blueprint
        # @param value [Numeric | Array[Numeric]] The metric value
        # @return [String] The complete StatsD datagram
        def to_datagram(value)
          packed_value = if value.is_a?(Array)
            value.join(":")
          else
            value.to_s
          end

          # Fast path: no tag values (static metrics)
          return @datagram_blueprint % packed_value if @tag_values.empty?

          # Sanitize string and symbol values (other types handled by sprintf %s)
          values = @tag_values.map do |arg|
            if arg.is_a?(String)
              /[|,]/.match?(arg) ? arg.tr("|,", "") : arg
            elsif arg.is_a?(Symbol)
              str = arg.to_s
              /[|,]/.match?(str) ? str.tr("|,", "") : str
            else
              arg
            end
          end

          # Prepend the metric value
          values.unshift(packed_value)

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

          def increment(__value__ = 1, **tags)
            require_define_to_be_called
          end
        end
      end

      # Gauge metric type
      class Gauge < CompiledMetric
        class << self
          def type
            "g"
          end

          def method_name
            :gauge
          end

          def default_value
            nil
          end

          def gauge(__value__ = 1, **tags)
            require_define_to_be_called
          end
        end
      end

      # Distribution metric type
      class Distribution < CompiledMetric
        class << self
          def type
            "d"
          end

          def method_name
            :distribution
          end

          def default_value
            0
          end

          def allow_measuring_latency
            true
          end

          def distribution(__value__ = 0, **tags)
            require_define_to_be_called
          end
        end
      end
    end
  end
end
