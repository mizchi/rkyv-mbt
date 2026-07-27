///|
/// The archive size used for native Time Profiler runs. It is large enough to
/// exercise the SIMD materializer while still fitting comfortably in cache.
let profile_element_count = 4096

///|
/// Builds the input once per profile phase. Encoding is deliberately outside
/// the repeated reader loops because rkyv consumers receive existing archives.
fn profile_archive() -> Bytes {
  let values : Array[UInt] = []
  for index in 0..<profile_element_count {
    values.push(index.reinterpret_as_uint())
  }
  @rkyv.encode_vec_u32(values)
}

///|
/// Returns a validated view over the profile archive.
fn profile_view() -> @rkyv.U32VecView {
  let reader = @rkyv.Reader::new(profile_archive())
  reader.read_vec_u32(profile_element_count * 4) catch {
    _ => abort("the profiling archive must be valid")
  }
}

///|
/// Repeatedly validates the default-format `ArchivedVec<u32>` header.
fn run_header_workload(iterations : Int) -> Int {
  let reader = @rkyv.Reader::new(profile_archive())
  let root_offset = profile_element_count * 4
  let mut checksum = 0
  for _ in 0..<iterations {
    let length = reader.read_vec_u32_length(root_offset) catch {
      _ => abort("the profiling archive must be valid")
    }
    checksum = checksum + length
  }
  checksum
}

///|
/// Repeatedly resolves lazy elements from one fully validated view.
fn run_lazy_workload(iterations : Int) -> UInt {
  let view = profile_view()
  let mut checksum = 0U
  let mut index = 0
  for _ in 0..<iterations {
    match view.get(index) {
      Some(value) => checksum = checksum + value
      None => abort("the profiling index must be in range")
    }
    index = if index + 1 == profile_element_count { 0 } else { index + 1 }
  }
  checksum
}

///|
/// Repeatedly materializes every vector element and consumes every result.
/// Consuming the array prevents the optimizer from discarding SIMD loads.
fn run_eager_workload(iterations : Int) -> UInt {
  let view = profile_view()
  let mut checksum = 0U
  for _ in 0..<iterations {
    let values = view.to_array_fast()
    for value in values {
      checksum = checksum + value
    }
  }
  checksum
}

///|
/// Repeatedly materializes to fixed-size storage without converting it to a
/// growable `Array`.
fn run_fixed_array_workload(iterations : Int) -> UInt {
  let view = profile_view()
  let mut checksum = 0U
  for _ in 0..<iterations {
    let values = view.to_fixed_array_fast()
    for value in values {
      checksum = checksum + value
    }
  }
  checksum
}

///|
/// Repeatedly fills one caller-owned buffer. Its allocation stays outside the
/// profile loop, so the profile isolates decoding and copying work.
fn run_copy_workload(iterations : Int) -> UInt {
  let view = profile_view()
  let destination : FixedArray[UInt] = FixedArray::make(
    profile_element_count, 0U,
  )
  let mut checksum = 0U
  for _ in 0..<iterations {
    view.copy_into(destination) catch {
      _ => abort("the profiling destination must fit")
    }
    checksum = checksum + destination[profile_element_count / 2]
  }
  checksum
}

///|
/// Revalidates the archive then copies into one caller-owned buffer. This
/// models callers that do not retain views between input archives.
fn run_direct_copy_workload(iterations : Int) -> UInt {
  let archive = profile_archive()
  let root_offset = profile_element_count * 4
  let destination : FixedArray[UInt] = FixedArray::make(
    profile_element_count, 0U,
  )
  let mut checksum = 0U
  for _ in 0..<iterations {
    let reader = @rkyv.Reader::new(archive)
    let _ = reader.read_vec_u32_into(root_offset, destination) catch {
      _ => abort("the profiling destination must fit")
    }
    checksum = checksum + destination[profile_element_count / 2]
  }
  checksum
}

///|
/// A several-second native workload for `moon run --profile cmd/profile`.
/// Keep the checksum output: it makes all six measured paths observable.
fn main {
  let header = run_header_workload(100000000)
  let lazy_checksum = run_lazy_workload(400000000)
  let eager = run_eager_workload(200000)
  let fixed = run_fixed_array_workload(200000)
  let copied = run_copy_workload(200000)
  let direct = run_direct_copy_workload(200000)
  println(
    "header=\{header}, lazy=\{lazy_checksum}, eager=\{eager}, fixed=\{fixed}, copied=\{copied}, direct=\{direct}",
  )
}
