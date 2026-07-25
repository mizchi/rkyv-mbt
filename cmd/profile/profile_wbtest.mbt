///|
/// The profiling workload must consume the reader results so the release
/// compiler cannot remove the paths that Time Profiler is meant to sample.
test "profile workloads retain reader results" {
  assert_eq(run_header_workload(3), 12288)
  assert_eq(run_lazy_workload(8), 28U)
  assert_eq(run_eager_workload(1), 8386560U)
}
