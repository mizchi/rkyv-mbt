///|
/// Builds an rkyv `Vec<u32>` archive once, outside the measured section.
fn benchmark_vec_archive(element_count : Int) -> Bytes {
  let values : Array[UInt] = []
  for index in 0..<element_count {
    values.push(index.reinterpret_as_uint())
  }
  encode_vec_u32(values)
}

///|
/// Resolves one selected element from a 4,096-element archive. The measured
/// section includes safe `Reader`/view construction, then uses the validated
/// view's non-failing `get` fast path without allocating an element array.
test "ArchivedVec<u32> validated selected element / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let selected : Result[UInt?, RkyvError] = match
      reader.read_vec_u32(root_offset) {
      Ok(view) => Ok(view.get(element_count / 2))
      Err(error) => Err(error)
    }
    b.keep(selected)
  })
}

///|
/// Materializes the same 4,096-element archive into a MoonBit array. The
/// default little-endian path loads four `u32` values per v128 block.
test "ArchivedVec<u32> SIMD eager materialization / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let values : Result[Array[UInt], RkyvError] = match
      reader.read_vec_u32(root_offset) {
      Ok(view) => view.to_array()
      Err(error) => Err(error)
    }
    b.keep(values)
  })
}
