# frozen_string_literal: true

class StatsD::Instrument::StatsDDatagramBuilder
  unless Regexp.method_defined?(:match?) # for ruby 2.3
    module RubyBackports
      refine Regexp do
        def match?(str)
          (self =~ str) != nil
        end
      end
    end

    using RubyBackports
  end

  def initialize(prefix: nil, default_tags: nil)
    @prefix = prefix.nil? ? "" : "#{normalize_name(prefix)}."
  end

  def c(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'c', sample_rate, tags)
  end

  def g(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'g', sample_rate, tags)
  end

  def ms(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'ms', sample_rate, tags)
  end

  def s(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'s', sample_rate, tags)
  end

  def h(name, value, sample_rate, tags)
    # TODO: raise or log?
  end

  def d(name, value, sample_rate, tags)
    # TODO: raise or log?
  end

  protected

  attr_reader :prefix, :default_tags

  # Utility function to convert tags to the canonical form.
  #
  # - Tags specified as key value pairs will be converted into an array
  # - Tags are normalized to only use word characters and underscores.
  #
  # @param tags [Array<String>, Hash<String, String>, nil] Tags specified in any form.
  # @return [Array<String>, nil] the list of tags in canonical form.
  def normalize_tags(tags)
    return [] unless tags
    tags = tags.map { |k, v| "#{k}:#{v}" } if tags.is_a?(Hash)

    # Fast path when no string replacement is needed
    return tags unless tags.any? { /[|,]/.match?(tags) }
    tags.map { |tag| tag.tr('|,', '') }
  end

  def normalize_name(name)
    # Fast path when no normalization is needed to avoid copying the string
    return name unless /[:|@]/.match?(name)
    name.tr(':|@', '_')
  end

  def generate_generic_datagram(name, value, type, sample_rate, _tags)
    datagram = +"#{@prefix}#{normalize_name(name)}:#{value}|#{type}"
    datagram << "|@#{sample_rate}" if sample_rate && sample_rate < 1
    datagram
  end
end
