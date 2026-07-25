///|
/// A view over an rkyv archive. It keeps the caller's `Bytes` buffer and
/// never copies data while resolving primitive values or relative pointers.
pub struct Reader {
  bytes : Bytes
  format : Format
}

///|
/// The two fields that make up an `ArchivedVec<T>` header.
pub struct VecHeader {
  data_offset : Int
  length : Int
} derive(Debug, Eq)

///|
/// A zero-copy typed view of an `ArchivedVec<u32>`. Generated bindings can
/// retain this view and resolve only the elements requested by their caller.
pub struct U32VecView {
  reader : Reader
  data_offset : Int
  length : Int
}

///|
/// `Bytes` and `FixedArray[Byte]` have the same immutable backing layout.
/// This private identity view is used only as the read-only source for the
/// experimental SIMD materializer below.
fn bytes_as_fixed_array(bytes : Bytes) -> FixedArray[Byte] = "%identity"

///|
/// Native `UInt` elements occupy four bytes, matching rkyv's archived `u32`.
/// The native stub bulk-copies an already validated little-endian span into a
/// temporary `FixedArray[UInt]`; no alias between differently typed arrays is
/// exposed to MoonBit's ownership system.
#cfg(target="native")
#borrow(source, destination)
extern "C" fn copy_validated_u32s_native(
  source : FixedArray[Byte],
  source_offset : Int,
  destination : FixedArray[UInt],
  length : Int,
) -> Unit = "rkyv_copy_validated_u32s"

///|
/// Creates a reader for rkyv's default format.
pub fn Reader::new(bytes : Bytes) -> Reader {
  { bytes, format: default_format() }
}

///|
/// Creates a reader with an explicitly selected rkyv format.
pub fn Reader::with_format(bytes : Bytes, format : Format) -> Reader {
  { bytes, format }
}

///|
/// Returns the archive's backing bytes without copying them.
pub fn Reader::bytes(self : Reader) -> Bytes {
  self.bytes
}

///|
/// Ensures that `[offset, offset + size)` is wholly contained in the input.
fn Reader::require(
  self : Reader,
  offset : Int,
  size : Int,
) -> Result[Unit, RkyvError] {
  let length = self.bytes.length()
  if offset < 0 || size < 0 || offset > length || size > length - offset {
    Err(RkyvError::OutOfBounds(offset~, size~, length~))
  } else {
    Ok(())
  }
}

///|
/// Validates that a fixed-size archived value is wholly contained in the
/// input. Generated nested views use this before retaining an inline offset.
pub fn Reader::validate_range(
  self : Reader,
  offset : Int,
  size : Int,
) -> Result[Unit, RkyvError] {
  self.require(offset, size)
}

///|
/// Gets the byte offset of a root whose archived representation has `size`
/// bytes. rkyv writes dependencies first and puts the root at the end.
pub fn Reader::root_offset(self : Reader, size : Int) -> Result[Int, RkyvError] {
  match self.require(self.bytes.length() - size, size) {
    Ok(_) => Ok(self.bytes.length() - size)
    Err(error) => Err(error)
  }
}

///|
/// Reads an unsigned 8-bit integer.
pub fn Reader::read_u8(self : Reader, offset : Int) -> Result[Byte, RkyvError] {
  match self.require(offset, 1) {
    Ok(_) => Ok(self.bytes[offset])
    Err(error) => Err(error)
  }
}

///|
/// Reads a signed 8-bit integer.
pub fn Reader::read_i8(self : Reader, offset : Int) -> Result[Int, RkyvError] {
  match self.read_u8(offset) {
    Ok(value) => {
      let bits = value.to_uint().reinterpret_as_int()
      Ok(if bits >= 128 { bits - 256 } else { bits })
    }
    Err(error) => Err(error)
  }
}

///|
/// Reads an unsigned 16-bit integer using the archive's configured endianness.
pub fn Reader::read_u16(self : Reader, offset : Int) -> Result[UInt, RkyvError] {
  match self.require(offset, 2) {
    Err(error) => Err(error)
    Ok(_) => {
      let first = self.bytes[offset].to_uint()
      let second = self.bytes[offset + 1].to_uint()
      let value = match self.format.endian {
        Endian::Little => first | (second << 8)
        Endian::Big => (first << 8) | second
      }
      Ok(value)
    }
  }
}

///|
/// Reads a signed 16-bit integer.
pub fn Reader::read_i16(self : Reader, offset : Int) -> Result[Int, RkyvError] {
  match self.read_u16(offset) {
    Ok(value) => {
      let bits = value.reinterpret_as_int()
      Ok(if bits >= 0x8000 { bits - 0x10000 } else { bits })
    }
    Err(error) => Err(error)
  }
}

///|
/// Decodes a `u32` after the caller has established that all four bytes are
/// in range. `U32VecView` may use this because its constructor validates the
/// complete archived element span before retaining the view.
fn Reader::read_u32_in_validated_range(self : Reader, offset : Int) -> UInt {
  let b0 = self.bytes.unsafe_get(offset).to_uint()
  let b1 = self.bytes.unsafe_get(offset + 1).to_uint()
  let b2 = self.bytes.unsafe_get(offset + 2).to_uint()
  let b3 = self.bytes.unsafe_get(offset + 3).to_uint()
  match self.format.endian {
    Endian::Little => b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    Endian::Big => (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  }
}

///|
/// Reads an unsigned 32-bit integer using the archive's configured endianness.
pub fn Reader::read_u32(self : Reader, offset : Int) -> Result[UInt, RkyvError] {
  match self.require(offset, 4) {
    Err(error) => Err(error)
    Ok(_) => Ok(self.read_u32_in_validated_range(offset))
  }
}

///|
/// Reads a signed 32-bit integer.
pub fn Reader::read_i32(self : Reader, offset : Int) -> Result[Int, RkyvError] {
  match self.read_u32(offset) {
    Ok(value) => Ok(value.reinterpret_as_int())
    Err(error) => Err(error)
  }
}

///|
/// Reads an IEEE 754 single-precision float without changing its bit pattern.
pub fn Reader::read_f32(
  self : Reader,
  offset : Int,
) -> Result[Float, RkyvError] {
  match self.read_u32(offset) {
    Ok(value) => Ok(Float::reinterpret_from_uint(value))
    Err(error) => Err(error)
  }
}

///|
/// Reads rkyv's one-byte boolean representation.
pub fn Reader::read_bool(
  self : Reader,
  offset : Int,
) -> Result[Bool, RkyvError] {
  match self.read_u8(offset) {
    Ok(value) => Ok(value != b'\x00')
    Err(error) => Err(error)
  }
}

///|
/// Reads an unsigned 64-bit integer using the archive's configured endianness.
pub fn Reader::read_u64(
  self : Reader,
  offset : Int,
) -> Result[UInt64, RkyvError] {
  match self.require(offset, 8) {
    Err(error) => Err(error)
    Ok(_) => {
      let b0 = self.bytes[offset].to_uint64()
      let b1 = self.bytes[offset + 1].to_uint64()
      let b2 = self.bytes[offset + 2].to_uint64()
      let b3 = self.bytes[offset + 3].to_uint64()
      let b4 = self.bytes[offset + 4].to_uint64()
      let b5 = self.bytes[offset + 5].to_uint64()
      let b6 = self.bytes[offset + 6].to_uint64()
      let b7 = self.bytes[offset + 7].to_uint64()
      let value = match self.format.endian {
        Endian::Little =>
          b0 |
          (b1 << 8) |
          (b2 << 16) |
          (b3 << 24) |
          (b4 << 32) |
          (b5 << 40) |
          (b6 << 48) |
          (b7 << 56)
        Endian::Big =>
          (b0 << 56) |
          (b1 << 48) |
          (b2 << 40) |
          (b3 << 32) |
          (b4 << 24) |
          (b5 << 16) |
          (b6 << 8) |
          b7
      }
      Ok(value)
    }
  }
}

///|
/// Reads a signed 64-bit integer.
pub fn Reader::read_i64(
  self : Reader,
  offset : Int,
) -> Result[Int64, RkyvError] {
  match self.read_u64(offset) {
    Ok(value) => Ok(value.reinterpret_as_int64())
    Err(error) => Err(error)
  }
}

///|
/// Reads an IEEE 754 double-precision float without changing its bit pattern.
pub fn Reader::read_f64(
  self : Reader,
  offset : Int,
) -> Result[Double, RkyvError] {
  match self.read_u64(offset) {
    Ok(value) => Ok(value.reinterpret_as_double())
    Err(error) => Err(error)
  }
}

///|
/// Reads rkyv's fixed-width archived `usize`. Offsets larger than MoonBit's
/// addressable `Int` range are rejected instead of wrapping.
pub fn Reader::read_usize(
  self : Reader,
  offset : Int,
) -> Result[Int, RkyvError] {
  match self.format.pointer_width {
    16 =>
      match self.read_u16(offset) {
        Ok(value) => Ok(value.reinterpret_as_int())
        Err(error) => Err(error)
      }
    32 =>
      match self.read_u32(offset) {
        Ok(value) =>
          if value > 0x7fff_ffffU {
            Err(RkyvError::LengthOverflow(value.reinterpret_as_int()))
          } else {
            Ok(value.reinterpret_as_int())
          }
        Err(error) => Err(error)
      }
    64 =>
      match self.read_u64(offset) {
        Ok(value) =>
          if value > 0x7fff_ffffUL {
            Err(RkyvError::LengthOverflow(value.to_int()))
          } else {
            Ok(value.to_int())
          }
        Err(error) => Err(error)
      }
    width => Err(RkyvError::InvalidPointerWidth(width))
  }
}

///|
/// Reads the signed raw offset stored in an rkyv relative pointer.
pub fn Reader::read_rel_ptr_offset(
  self : Reader,
  offset : Int,
) -> Result[Int, RkyvError] {
  match self.format.pointer_width {
    16 => self.read_i16(offset)
    32 => self.read_i32(offset)
    64 =>
      match self.read_i64(offset) {
        Ok(value) =>
          if value < -2147483648L || value > 2147483647L {
            Err(RkyvError::InvalidRelativePointer(value.to_int()))
          } else {
            Ok(value.to_int())
          }
        Err(error) => Err(error)
      }
    width => Err(RkyvError::InvalidPointerWidth(width))
  }
}

///|
/// Resolves an ordinary rkyv relative pointer. `ArchivedString` is the one
/// exception: its pointer is relative to the string representation's start.
pub fn Reader::read_rel_ptr(
  self : Reader,
  offset : Int,
) -> Result[Int, RkyvError] {
  match self.read_rel_ptr_offset(offset) {
    Err(error) => Err(error)
    Ok(relative) => {
      let target = offset + relative
      match self.require(target, 0) {
        Ok(_) => Ok(target)
        Err(_) => Err(RkyvError::InvalidRelativePointer(relative))
      }
    }
  }
}

///|
/// Reads the header of an `ArchivedVec<T>`. Element decoding remains a
/// schema concern and belongs in generated or hand-written bindings.
pub fn Reader::read_vec_header(
  self : Reader,
  offset : Int,
) -> Result[VecHeader, RkyvError] {
  match self.format.pointer_bytes() {
    Err(error) => Err(error)
    Ok(pointer_bytes) =>
      match self.read_rel_ptr_offset(offset) {
        Err(error) => Err(error)
        Ok(relative) =>
          match self.read_usize(offset + pointer_bytes) {
            Err(error) => Err(error)
            Ok(length) => {
              let data_offset = offset + relative
              match self.require(data_offset, 0) {
                Ok(_) => Ok({ data_offset, length })
                Err(_) => Err(RkyvError::InvalidRelativePointer(relative))
              }
            }
          }
      }
  }
}

///|
/// Reads and validates a default-format `ArchivedVec<u32>` directly as a view.
/// The rkyv default profile is little-endian with 32-bit relative pointers and
/// lengths, so its header is always eight bytes. Returning the view directly
/// avoids allocating an intermediate `VecHeader`/`Result` pair on the lazy
/// hot path.
#warnings("-alert_experimental")
fn Reader::read_default_vec_u32(
  self : Reader,
  offset : Int,
) -> Result[U32VecView, RkyvError] {
  let input_length = self.bytes.length()
  if offset < 0 || offset > input_length - 8 {
    let size = 8
    let length = input_length
    return Err(RkyvError::OutOfBounds(offset~, size~, length~))
  }
  let header = @v128.v128_load64_zero(bytes_as_fixed_array(self.bytes), offset)
  let relative = @v128.i32x4_extract_lane(header, 0).reinterpret_as_int()
  let raw_length = @v128.i32x4_extract_lane(header, 1)
  if raw_length > 0x7fff_ffffU {
    return Err(RkyvError::LengthOverflow(raw_length.reinterpret_as_int()))
  }
  let length = raw_length.reinterpret_as_int()
  let data_offset = offset + relative
  if data_offset < 0 || data_offset > input_length {
    return Err(RkyvError::InvalidRelativePointer(relative))
  }
  let available = input_length - data_offset
  if length > available / 4 {
    Err(RkyvError::InvalidCollectionLength(length))
  } else {
    Ok({ reader: self, data_offset, length })
  }
}

///|
/// Reads an `ArchivedVec<T>` header and validates its complete element range.
/// Generated bindings supply the archived element size measured by the Rust
/// compiler, preventing a corrupted length from escaping as a lazy view.
pub fn Reader::read_vec_header_with_element_size(
  self : Reader,
  offset : Int,
  element_size : Int,
) -> Result[VecHeader, RkyvError] {
  if element_size <= 0 {
    return Err(RkyvError::InvalidElementSize(element_size))
  }
  match self.read_vec_header(offset) {
    Err(error) => Err(error)
    Ok(header) => {
      let available = self.bytes.length() - header.data_offset
      if header.length > available / element_size {
        Err(RkyvError::InvalidCollectionLength(header.length))
      } else {
        Ok(header)
      }
    }
  }
}

///|
/// Reads an `ArchivedVec<u32>` as a zero-copy typed view. The whole byte span
/// is validated before returning so subsequent indexing is bounded by the
/// archive rather than a potentially corrupted archived length.
pub fn Reader::read_vec_u32(
  self : Reader,
  offset : Int,
) -> Result[U32VecView, RkyvError] {
  if self.format.endian == Endian::Little && self.format.pointer_width == 32 {
    self.read_default_vec_u32(offset)
  } else {
    match self.read_vec_header_with_element_size(offset, 4) {
      Err(error) => Err(error)
      Ok(header) =>
        Ok({
          reader: self,
          data_offset: header.data_offset,
          length: header.length,
        })
    }
  }
}

///|
/// Returns the number of elements in the archived vector without decoding it.
pub fn U32VecView::length(self : U32VecView) -> Int {
  self.length
}

///|
/// Returns the byte offset of the first `u32` element within the archive.
/// Integrations that store an entire archive in 32-bit shared memory can
/// convert this to a word offset after checking that it is divisible by four.
pub fn U32VecView::data_byte_offset(self : U32VecView) -> Int {
  self.data_offset
}

///|
/// Resolves an element from a fully validated archived vector. `read_vec_u32`
/// verifies the complete element span before constructing this view, so a
/// valid in-range index cannot fail byte-range validation. Out-of-range indices
/// return `None`.
pub fn U32VecView::get(self : U32VecView, index : Int) -> UInt? {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_u32_in_validated_range(self.data_offset + index * 4))
  }
}

///|
/// Resolves one element without copying the rest of the archived vector.
/// An index outside the vector's logical range returns `Ok(None)`.
pub fn U32VecView::at(
  self : U32VecView,
  index : Int,
) -> Result[UInt?, RkyvError] {
  Ok(self.get(index))
}

///|
/// Uses a native bulk copy to fill contiguous u32 storage. Native C compilers
/// lower this fixed-size-width copy to vector instructions when profitable;
/// the final conversion returns the public growable `Array` representation.
#cfg(target="native")
fn U32VecView::materialize_little_endian(self : U32VecView) -> Array[UInt] {
  let storage : FixedArray[UInt] = FixedArray::make(self.length, 0U)
  let source = bytes_as_fixed_array(self.reader.bytes)
  copy_validated_u32s_native(source, self.data_offset, storage, self.length)
  Array::from_fixed_array(storage)
}

///|
/// Other targets retain lane extraction because their `Array[UInt]` backing
/// representation is not a native contiguous 32-bit byte buffer.
#cfg(not(target="native"))
#warnings("-alert_experimental")
fn U32VecView::materialize_little_endian(self : U32VecView) -> Array[UInt] {
  let values : Array[UInt] = Array::make(self.length, 0U)
  let bytes = bytes_as_fixed_array(self.reader.bytes)
  let block_count = self.length / 4
  for block in 0..<block_count {
    let index = block * 4
    let lanes = @v128.v128_load(bytes, self.data_offset + index * 4)
    values.unsafe_set(index, @v128.i32x4_extract_lane(lanes, 0))
    values.unsafe_set(index + 1, @v128.i32x4_extract_lane(lanes, 1))
    values.unsafe_set(index + 2, @v128.i32x4_extract_lane(lanes, 2))
    values.unsafe_set(index + 3, @v128.i32x4_extract_lane(lanes, 3))
  }
  let tail_start = block_count * 4
  for index in tail_start..<self.length {
    values.unsafe_set(
      index,
      self.reader.read_u32_in_validated_range(self.data_offset + index * 4),
    )
  }
  values
}

///|
/// Decodes every element after `read_vec_u32` has validated the full element
/// span. Unlike the compatibility wrapper, this cannot fail.
#warnings("-alert_experimental")
pub fn U32VecView::to_array_fast(self : U32VecView) -> Array[UInt] {
  match self.reader.format.endian {
    Endian::Little => self.materialize_little_endian()
    Endian::Big => {
      let values : Array[UInt] = Array::make(self.length, 0U)
      for index in 0..<self.length {
        values.unsafe_set(
          index,
          self.reader.read_u32_in_validated_range(self.data_offset + index * 4),
        )
      }
      values
    }
  }
}

///|
/// Decodes every element into a MoonBit array. Keep the `U32VecView` when a
/// caller only needs selected elements; use this at API boundaries that need
/// an owned collection.
pub fn U32VecView::to_array(
  self : U32VecView,
) -> Result[Array[UInt], RkyvError] {
  Ok(self.to_array_fast())
}

///|
/// Resolves an `ArchivedOption<T>` tag into the offset of its present value.
/// The caller supplies the archived alignment of `T`; this keeps type-specific
/// layout in generated bindings while centralizing rkyv's tag/padding rule.
pub fn Reader::read_option_value_offset(
  self : Reader,
  offset : Int,
  value_alignment : Int,
) -> Result[Int?, RkyvError] {
  if value_alignment <= 0 {
    return Err(RkyvError::InvalidAlignment(value_alignment))
  }
  match self.read_u8(offset) {
    Err(error) => Err(error)
    Ok(tag) =>
      if tag == b'\x00' {
        Ok(None)
      } else {
        let after_tag = offset + 1
        let value_offset = (after_tag + value_alignment - 1) /
          value_alignment *
          value_alignment
        match self.require(value_offset, 0) {
          Ok(_) => Ok(Some(value_offset))
          Err(error) => Err(error)
        }
      }
  }
}

///|
/// Decodes a valid UTF-8 subrange after checking its bounds.
fn Reader::read_text(
  self : Reader,
  offset : Int,
  length : Int,
) -> Result[String, RkyvError] {
  match self.require(offset, length) {
    Err(error) => Err(error)
    Ok(_) => {
      let text = @utf8.decode(self.bytes[offset:offset + length]) catch {
        _ => return Err(RkyvError::InvalidUtf8)
      }
      Ok(text)
    }
  }
}

///|
/// Decodes the marked length in an out-of-line `ArchivedString`.
fn Reader::read_out_of_line_string_length(
  self : Reader,
  offset : Int,
) -> Result[Int, RkyvError] {
  match self.format.pointer_width {
    16 =>
      match self.read_u16(offset) {
        Ok(value) =>
          Ok(
            (value & 0x3fU).reinterpret_as_int() +
            (value >> 8).reinterpret_as_int() * 64,
          )
        Err(error) => Err(error)
      }
    32 =>
      match self.read_u32(offset) {
        Ok(value) =>
          Ok(
            (value & 0x3fU).reinterpret_as_int() +
            (value >> 8).reinterpret_as_int() * 64,
          )
        Err(error) => Err(error)
      }
    64 => Err(RkyvError::InvalidPointerWidth(64))
    width => Err(RkyvError::InvalidPointerWidth(width))
  }
}

///|
/// Reads rkyv 0.8's hybrid inline/out-of-line `ArchivedString` layout.
pub fn Reader::read_string(
  self : Reader,
  offset : Int,
) -> Result[String, RkyvError] {
  match self.format.pointer_bytes() {
    Err(error) => Err(error)
    Ok(pointer_bytes) => {
      let inline_capacity = pointer_bytes * 2
      match self.require(offset, inline_capacity) {
        Err(error) => Err(error)
        Ok(_) => {
          let first = self.bytes[offset].to_int()
          if (first & 0xc0) != 0x80 {
            let mut length = 0
            while length < inline_capacity &&
                  self.bytes[offset + length] != b'\xff' {
              length = length + 1
            }
            self.read_text(offset, length)
          } else {
            match self.read_out_of_line_string_length(offset) {
              Err(error) => Err(error)
              Ok(length) =>
                match self.read_rel_ptr_offset(offset + pointer_bytes) {
                  Err(error) => Err(error)
                  Ok(relative) => {
                    let data_offset = offset + relative
                    self.read_text(data_offset, length)
                  }
                }
            }
          }
        }
      }
    }
  }
}
