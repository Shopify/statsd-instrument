# frozen_string_literal: true

module StatsD::Instrument::Backends
  # The null backend does nothing when receiving a metric, effectively disabling the gem completely.
  class NullBackend < StatsD::Instrument::Backend
    def sample?(_sample_rate)
      true
    end

    def collect_metric(metric)
    end
  end
end
