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
/// section includes `Reader`/view construction but creates no element array.
test "ArchivedVec<u32> lazy selected element / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let selected : Result[UInt?, RkyvError] = match
      reader.read_vec_u32(root_offset) {
      Ok(view) => view.at(element_count / 2)
      Err(error) => Err(error)
    }
    b.keep(selected)
  })
}

///|
/// Materializes the same 4,096-element archive into a MoonBit array. This is
/// the eager baseline for callers that need every element.
test "ArchivedVec<u32> eager materialization / 4K" (b : @bench.T) {
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
