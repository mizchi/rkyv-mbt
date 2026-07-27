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
/// Profiles the fixed cost of constructing a Reader around existing bytes.
test "profile Reader construction / 4K" (b : @bench.T) {
  let archive = benchmark_vec_archive(4096)
  b.bench(fn() { b.keep(Reader::new(archive)) })
}

///|
/// Profiles default-format header parsing and complete span validation.
test "profile ArchivedVec<u32> length validation / 4K" (b : @bench.T) {
  let element_count = 4096
  let reader = Reader::new(benchmark_vec_archive(element_count))
  let root_offset = element_count * 4
  b.bench(fn() {
    let length = reader.read_vec_u32_length(root_offset) catch { _ => -1 }
    b.keep(length)
  })
}

///|
/// Profiles only a selected element read from a prevalidated lazy view.
test "profile validated ArchivedVec<u32>::get / 4K" (b : @bench.T) {
  let element_count = 4096
  let reader = Reader::new(benchmark_vec_archive(element_count))
  let view = reader.read_vec_u32(element_count * 4) catch {
    _ => abort("benchmark archive must be valid")
  }
  b.bench(fn() { b.keep(view.get(element_count / 2)) })
}

///|
/// Includes Reader and validated-view construction for one selected element.
test "ArchivedVec<u32> checked selected element / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let view = reader.read_vec_u32(root_offset) catch {
      _ => abort("benchmark archive must be valid")
    }
    b.keep(view.get(element_count / 2))
  })
}

///|
/// Materializes the 4,096-element archive into a growable MoonBit array.
test "ArchivedVec<u32> SIMD eager materialization / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let view = reader.read_vec_u32(root_offset) catch {
      _ => abort("benchmark archive must be valid")
    }
    b.keep(view.to_array())
  })
}

///|
/// Materializes to a FixedArray without the growable-array conversion copy.
test "ArchivedVec<u32> FixedArray materialization / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  b.bench(fn() {
    let reader = Reader::new(archive)
    let view = reader.read_vec_u32(root_offset) catch {
      _ => abort("benchmark archive must be valid")
    }
    b.keep(view.to_fixed_array_fast())
  })
}

///|
/// Copies into a reusable contiguous FixedArray.
test "ArchivedVec<u32> copy into reused FixedArray / 4K" (b : @bench.T) {
  let element_count = 4096
  let reader = Reader::new(benchmark_vec_archive(element_count))
  let view = reader.read_vec_u32(element_count * 4) catch {
    _ => abort("benchmark archive must be valid")
  }
  let destination : FixedArray[UInt] = FixedArray::make(element_count, 0U)
  b.bench(fn() {
    view.copy_into(destination) catch {
      _ => abort("benchmark destination must fit")
    }
    b.keep(destination[element_count / 2])
  })
}

///|
/// Copies into a reusable window in a growable Array.
test "ArchivedVec<u32> copy into reused MutArrayView / 4K" (b : @bench.T) {
  let element_count = 4096
  let reader = Reader::new(benchmark_vec_archive(element_count))
  let view = reader.read_vec_u32(element_count * 4) catch {
    _ => abort("benchmark archive must be valid")
  }
  let storage : Array[UInt] = Array::make(element_count + 2, 0U)
  let destination = storage.mut_view(start=1, end=element_count + 1)
  b.bench(fn() {
    view.copy_into_mut_view(destination) catch {
      _ => abort("benchmark destination must fit")
    }
    b.keep(storage[element_count / 2 + 1])
  })
}

///|
/// Validates and copies in one call without retaining a caller-held view.
test "ArchivedVec<u32> direct copy into reused FixedArray / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  let destination : FixedArray[UInt] = FixedArray::make(element_count, 0U)
  b.bench(fn() {
    let reader = Reader::new(archive)
    let _ = reader.read_vec_u32_into(root_offset, destination) catch {
      _ => abort("benchmark destination must fit")
    }
    b.keep(destination[element_count / 2])
  })
}

///|
/// Measures the FixedArray plus ArrayView hand-off used by streaming callers.
test "ArchivedVec<u32> direct copy and ArrayView / 4K" (b : @bench.T) {
  let element_count = 4096
  let archive = benchmark_vec_archive(element_count)
  let root_offset = element_count * 4
  let destination : FixedArray[UInt] = FixedArray::make(element_count, 0U)
  b.bench(fn() {
    let reader = Reader::new(archive)
    let length = reader.read_vec_u32_into(root_offset, destination) catch {
      _ => abort("benchmark destination must fit")
    }
    b.keep(destination.view(end=length)[element_count / 2])
  })
}
