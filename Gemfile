# frozen_string_literal: true

source "https://rubygems.org"
gemspec

gem "rake"
gem "minitest"
gem "rspec"
gem "mocha"
gem "yard"
gem "rubocop", ">= 1.0"
gem "rubocop-shopify", require: false
gem "benchmark-ips"
gem "dogstatsd-ruby", "~> 5.0", require: false
gem "simplecov", require: false, group: :test

platform :mri do
  # only if Ruby is MRI && >= 3.2
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2")
    gem "vernier", require: false
  end

  # From Ruby >= 3.5, logger is not part of the stdlib anymore
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.5")
    gem "logger"
  end
end
