# Benchmark scripts

This directory contains benchmark scripts that can be used to gauge the
performance impact of changes.

As mentioned in the contributing guidelines, this library is used heavily in
production at Shopify in many of our hot code paths. This means that we care a
lot about changes not introducing performance regressions. Every pull request
that changes the code path to send metrics should include benchmarks
demonstrating the performance impact of the changes.

This directory contains two scripts to help with benchmarking.

- `send-metrics-to-dev-null-log` exercises the code path to construct metrics.
- `send-metrics-to-local-udp-listener` will also exercise the code path to
  actually send a StatsD packet over UDP.

To benchmark your changes:

1. Make sure the benchmark script will actually cover your changes.
   - If not, please create a new benchmark script that does.
   - Do not commit this script to the repository (yet), so it will continue to
     be available if you check out another branch.
2. Run these scripts on your pull request branch. The results will be stored in
   a temporary file.
3. Checkout the latest version of `main`.
4. Run the benchmark again. The benchmark script will now print a comparison
   between your branch and main.
5. Include the output in your pull request description.
