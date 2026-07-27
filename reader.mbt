///|
/// A view over an rkyv archive. It keeps the caller's `Bytes` buffer and
/// never copies data while resolving primitive values or relative pointers.
#valtype
pub struct Reader {
  bytes : Bytes
  format : Format
}

///|
/// The two fields that make up an `ArchivedVec<T>` header.
#valtype
pub struct VecHeader {
  data_offset : Int
  length : Int
} derive(Debug, Eq)

///|
/// A zero-copy typed view of an `ArchivedVec<u32>`. Generated bindings can
/// retain this view and resolve only the elements requested by their caller.
#valtype
pub struct U32VecView {
  bytes : Bytes
  format : Format
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
/// Returns a borrowed, bounds-checked range of the archive without copying.
/// This is intended for archived byte blobs and integrations that can consume
/// raw UTF-8 bytes directly. It does not validate a higher-level rkyv layout
/// or UTF-8; use `read_string` when a decoded, validated `String` is needed.
pub fn Reader::read_bytes_view(
  self : Reader,
  offset : Int,
  length : Int,
) -> BytesView raise RkyvError {
  self.require(offset, length)
  self.bytes.view(start=offset, end=offset + length)
}

///|
/// Ensures that `[offset, offset + size)` is wholly contained in the input.
fn Reader::require(
  self : Reader,
  offset : Int,
  size : Int,
) -> Unit raise RkyvError {
  let length = self.bytes.length()
  if offset < 0 || size < 0 || offset > length || size > length - offset {
    raise RkyvError::OutOfBounds(offset~, size~, length~)
  }
}

///|
/// Validates that a fixed-size archived value is wholly contained in the
/// input. Generated nested views use this before retaining an inline offset.
pub fn Reader::validate_range(
  self : Reader,
  offset : Int,
  size : Int,
) -> Unit raise RkyvError {
  self.require(offset, size)
}

///|
/// Enforces the recursion limit used by generated full-archive validators.
/// The constructor stays inside this package because `RkyvError` is a
/// `suberror` and cannot be constructed by generated client packages.
pub fn require_validation_depth(remaining_depth : Int) -> Unit raise RkyvError {
  if remaining_depth <= 0 {
    raise RkyvError::DepthLimit(remaining_depth)
  }
}

///|
/// Gets the byte offset of a root whose archived representation has `size`
/// bytes. rkyv writes dependencies first and puts the root at the end.
pub fn Reader::root_offset(self : Reader, size : Int) -> Int raise RkyvError {
  let offset = self.bytes.length() - size
  self.require(offset, size)
  offset
}

///|
/// Reads an unsigned 8-bit integer.
pub fn Reader::read_u8(self : Reader, offset : Int) -> Byte raise RkyvError {
  self.require(offset, 1)
  self.bytes[offset]
}

///|
/// Reads a signed 8-bit integer.
pub fn Reader::read_i8(self : Reader, offset : Int) -> Int raise RkyvError {
  let bits = self.read_u8(offset).to_uint().reinterpret_as_int()
  if bits >= 128 {
    bits - 256
  } else {
    bits
  }
}

///|
/// Reads an unsigned 16-bit integer using the archive's configured endianness.
pub fn Reader::read_u16(self : Reader, offset : Int) -> UInt raise RkyvError {
  self.require(offset, 2)
  let first = self.bytes[offset].to_uint()
  let second = self.bytes[offset + 1].to_uint()
  match self.format.endian {
    Endian::Little => first | (second << 8)
    Endian::Big => (first << 8) | second
  }
}

///|
/// Reads a signed 16-bit integer.
pub fn Reader::read_i16(self : Reader, offset : Int) -> Int raise RkyvError {
  let bits = self.read_u16(offset).reinterpret_as_int()
  if bits >= 0x8000 {
    bits - 0x10000
  } else {
    bits
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
pub fn Reader::read_u32(self : Reader, offset : Int) -> UInt raise RkyvError {
  self.require(offset, 4)
  self.read_u32_in_validated_range(offset)
}

///|
/// Reads a signed 32-bit integer.
pub fn Reader::read_i32(self : Reader, offset : Int) -> Int raise RkyvError {
  self.read_u32(offset).reinterpret_as_int()
}

///|
/// Reads an IEEE 754 single-precision float without changing its bit pattern.
pub fn Reader::read_f32(self : Reader, offset : Int) -> Float raise RkyvError {
  Float::reinterpret_from_uint(self.read_u32(offset))
}

///|
/// Reads rkyv's one-byte boolean representation.
pub fn Reader::read_bool(self : Reader, offset : Int) -> Bool raise RkyvError {
  self.read_u8(offset) != b'\x00'
}

///|
/// Reads a boolean for an untrusted archive. Unlike `read_bool`, this rejects
/// values other than rkyv's canonical `0` and `1` discriminants.
pub fn Reader::read_bool_strict(
  self : Reader,
  offset : Int,
) -> Bool raise RkyvError {
  match self.read_u8(offset) {
    b'\x00' => false
    b'\x01' => true
    value => raise RkyvError::InvalidBool(value)
  }
}

///|
/// Reads a `#[repr(u8)]` enum tag for an untrusted archive. The accepted tags
/// are supplied by generated bindings; an unknown value is raised from inside
/// this package because `RkyvError` is intentionally a read-only suberror to
/// downstream MoonBit packages.
pub fn Reader::read_union_tag(
  self : Reader,
  offset : Int,
  accepted : Array[Byte],
) -> Byte raise RkyvError {
  let value = self.read_u8(offset)
  for tag in accepted {
    if tag == value {
      return value
    }
  }
  raise RkyvError::InvalidUnionTag(value)
}

///|
/// Reads an unsigned 64-bit integer using the archive's configured endianness.
pub fn Reader::read_u64(self : Reader, offset : Int) -> UInt64 raise RkyvError {
  self.require(offset, 8)
  let b0 = self.bytes[offset].to_uint64()
  let b1 = self.bytes[offset + 1].to_uint64()
  let b2 = self.bytes[offset + 2].to_uint64()
  let b3 = self.bytes[offset + 3].to_uint64()
  let b4 = self.bytes[offset + 4].to_uint64()
  let b5 = self.bytes[offset + 5].to_uint64()
  let b6 = self.bytes[offset + 6].to_uint64()
  let b7 = self.bytes[offset + 7].to_uint64()
  match self.format.endian {
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
}

///|
/// Reads a signed 64-bit integer.
pub fn Reader::read_i64(self : Reader, offset : Int) -> Int64 raise RkyvError {
  self.read_u64(offset).reinterpret_as_int64()
}

///|
/// Reads an IEEE 754 double-precision float without changing its bit pattern.
pub fn Reader::read_f64(self : Reader, offset : Int) -> Double raise RkyvError {
  self.read_u64(offset).reinterpret_as_double()
}

///|
/// Reads rkyv's fixed-width archived `usize`. Offsets larger than MoonBit's
/// addressable `Int` range are rejected instead of wrapping.
pub fn Reader::read_usize(self : Reader, offset : Int) -> Int raise RkyvError {
  match self.format.pointer_width {
    16 => self.read_u16(offset).reinterpret_as_int()
    32 => {
      let value = self.read_u32(offset)
      if value > 0x7fff_ffffU {
        raise RkyvError::LengthOverflow(value.reinterpret_as_int())
      }
      value.reinterpret_as_int()
    }
    64 => {
      let value = self.read_u64(offset)
      if value > 0x7fff_ffffUL {
        raise RkyvError::LengthOverflow(value.to_int())
      }
      value.to_int()
    }
    width => raise RkyvError::InvalidPointerWidth(width)
  }
}

///|
/// Reads the signed raw offset stored in an rkyv relative pointer.
pub fn Reader::read_rel_ptr_offset(
  self : Reader,
  offset : Int,
) -> Int raise RkyvError {
  match self.format.pointer_width {
    16 => self.read_i16(offset)
    32 => self.read_i32(offset)
    64 => {
      let value = self.read_i64(offset)
      if value < -2147483648L || value > 2147483647L {
        raise RkyvError::InvalidRelativePointer(value.to_int())
      }
      value.to_int()
    }
    width => raise RkyvError::InvalidPointerWidth(width)
  }
}

///|
/// Resolves an ordinary rkyv relative pointer. `ArchivedString` is the one
/// exception: its pointer is relative to the string representation's start.
pub fn Reader::read_rel_ptr(self : Reader, offset : Int) -> Int raise RkyvError {
  let relative = self.read_rel_ptr_offset(offset)
  let target = offset + relative
  self.require(target, 0) catch {
    _ => raise RkyvError::InvalidRelativePointer(relative)
  }
  target
}

///|
/// Reads the header of an `ArchivedVec<T>`. Element decoding remains a
/// schema concern and belongs in generated or hand-written bindings.
pub fn Reader::read_vec_header(
  self : Reader,
  offset : Int,
) -> VecHeader raise RkyvError {
  let pointer_bytes = self.format.pointer_bytes()
  let relative = self.read_rel_ptr_offset(offset)
  let length = self.read_usize(offset + pointer_bytes)
  let data_offset = offset + relative
  self.require(data_offset, 0) catch {
    _ => raise RkyvError::InvalidRelativePointer(relative)
  }
  { data_offset, length }
}

///|
/// Reads and validates the length of a default-format `ArchivedVec<u32>`.
/// The rkyv default profile is little-endian with 32-bit relative pointers and
/// lengths, so its header is always eight bytes. This avoids creating a view
/// when a caller only needs the validated element count.
#warnings("-alert_experimental")
fn Reader::read_default_vec_u32_length(
  self : Reader,
  offset : Int,
) -> Int raise RkyvError {
  let input_length = self.bytes.length()
  if offset < 0 || offset > input_length - 8 {
    let size = 8
    let length = input_length
    raise RkyvError::OutOfBounds(offset~, size~, length~)
  }
  let header = @v128.v128_load64_zero(bytes_as_fixed_array(self.bytes), offset)
  let relative = @v128.i32x4_extract_lane(header, 0).reinterpret_as_int()
  let raw_length = @v128.i32x4_extract_lane(header, 1)
  if raw_length > 0x7fff_ffffU {
    raise RkyvError::LengthOverflow(raw_length.reinterpret_as_int())
  }
  let length = raw_length.reinterpret_as_int()
  let data_offset = offset + relative
  if data_offset < 0 || data_offset > input_length {
    raise RkyvError::InvalidRelativePointer(relative)
  }
  let available = input_length - data_offset
  if length > available / 4 {
    raise RkyvError::InvalidCollectionLength(length)
  }
  length
}

///|
/// Reads and validates a default-format `ArchivedVec<u32>` directly as a view.
/// The dedicated path retains the bytes only after the header and full element
/// span have passed validation.
#warnings("-alert_experimental")
fn Reader::read_default_vec_u32(
  self : Reader,
  offset : Int,
) -> U32VecView raise RkyvError {
  let input_length = self.bytes.length()
  if offset < 0 || offset > input_length - 8 {
    let size = 8
    let length = input_length
    raise RkyvError::OutOfBounds(offset~, size~, length~)
  }
  let header = @v128.v128_load64_zero(bytes_as_fixed_array(self.bytes), offset)
  let relative = @v128.i32x4_extract_lane(header, 0).reinterpret_as_int()
  let raw_length = @v128.i32x4_extract_lane(header, 1)
  if raw_length > 0x7fff_ffffU {
    raise RkyvError::LengthOverflow(raw_length.reinterpret_as_int())
  }
  let length = raw_length.reinterpret_as_int()
  let data_offset = offset + relative
  if data_offset < 0 || data_offset > input_length {
    raise RkyvError::InvalidRelativePointer(relative)
  }
  let available = input_length - data_offset
  if length > available / 4 {
    raise RkyvError::InvalidCollectionLength(length)
  }
  { bytes: self.bytes, format: self.format, data_offset, length }
}

///|
/// Reads an `ArchivedVec<T>` header and validates its complete element range.
/// Generated bindings supply the archived element size measured by the Rust
/// compiler, preventing a corrupted length from escaping as a lazy view.
pub fn Reader::read_vec_header_with_element_size(
  self : Reader,
  offset : Int,
  element_size : Int,
) -> VecHeader raise RkyvError {
  if element_size <= 0 {
    raise RkyvError::InvalidElementSize(element_size)
  }
  let header = self.read_vec_header(offset)
  let available = self.bytes.length() - header.data_offset
  if header.length > available / element_size {
    raise RkyvError::InvalidCollectionLength(header.length)
  }
  header
}

///|
/// Reads an `ArchivedVec<u32>` as a zero-copy typed view. The whole byte span
/// is validated before returning so subsequent indexing is bounded by the
/// archive rather than a potentially corrupted archived length.
pub fn Reader::read_vec_u32(
  self : Reader,
  offset : Int,
) -> U32VecView raise RkyvError {
  if self.format.endian == Endian::Little && self.format.pointer_width == 32 {
    self.read_default_vec_u32(offset)
  } else {
    let header = self.read_vec_header_with_element_size(offset, 4)
    {
      bytes: self.bytes,
      format: self.format,
      data_offset: header.data_offset,
      length: header.length,
    }
  }
}

///|
/// Validates an `ArchivedVec<u32>` and returns only its element count. Unlike
/// `read_vec_u32`, this does not create a `U32VecView` or retain the archive.
/// Use it for header-only consumers; use `read_vec_u32` when reading elements.
pub fn Reader::read_vec_u32_length(
  self : Reader,
  offset : Int,
) -> Int raise RkyvError {
  if self.format.endian == Endian::Little && self.format.pointer_width == 32 {
    self.read_default_vec_u32_length(offset)
  } else {
    self.read_vec_header_with_element_size(offset, 4).length
  }
}

///|
/// Validates an `ArchivedVec<u32>` and copies it into caller-owned fixed-size
/// storage. This convenience API does not expose or retain a view; a short
/// destination is left untouched and returns `DestinationTooSmall`. On
/// success, it returns the copied element count for making an `ArrayView`.
pub fn Reader::read_vec_u32_into(
  self : Reader,
  offset : Int,
  destination : FixedArray[UInt],
) -> Int raise RkyvError {
  let view = self.read_vec_u32(offset)
  view.copy_into(destination)
  view.length()
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
    let reader : Reader = { bytes: self.bytes, format: self.format }
    Some(reader.read_u32_in_validated_range(self.data_offset + index * 4))
  }
}

///|
/// Resolves one element without copying the rest of the archived vector.
/// An index outside the vector's logical range returns `None`.
pub fn U32VecView::at(self : U32VecView, index : Int) -> UInt? {
  self.get(index)
}

///|
/// Uses a native bulk copy to fill contiguous u32 storage. Native C compilers
/// lower this fixed-size-width copy to vector instructions when profitable.
#cfg(target="native")
fn U32VecView::copy_little_endian_into(
  self : U32VecView,
  destination : FixedArray[UInt],
) -> Unit {
  let source = bytes_as_fixed_array(self.bytes)
  copy_validated_u32s_native(source, self.data_offset, destination, self.length)
}

///|
/// Other targets use v128 lane extraction to fill the caller's fixed buffer.
#cfg(not(target="native"))
#warnings("-alert_experimental")
fn U32VecView::copy_little_endian_into(
  self : U32VecView,
  destination : FixedArray[UInt],
) -> Unit {
  let bytes = bytes_as_fixed_array(self.bytes)
  let reader : Reader = { bytes: self.bytes, format: self.format }
  let block_count = self.length / 4
  for block in 0..<block_count {
    let index = block * 4
    let lanes = @v128.v128_load(bytes, self.data_offset + index * 4)
    destination[index] = @v128.i32x4_extract_lane(lanes, 0)
    destination[index + 1] = @v128.i32x4_extract_lane(lanes, 1)
    destination[index + 2] = @v128.i32x4_extract_lane(lanes, 2)
    destination[index + 3] = @v128.i32x4_extract_lane(lanes, 3)
  }
  let tail_start = block_count * 4
  for index in tail_start..<self.length {
    destination[index] = reader.read_u32_in_validated_range(
      self.data_offset + index * 4,
    )
  }
}

///|
/// Writes into a destination whose capacity has already been checked.
fn U32VecView::copy_into_validated(
  self : U32VecView,
  destination : FixedArray[UInt],
) -> Unit {
  match self.format.endian {
    Endian::Little => self.copy_little_endian_into(destination)
    Endian::Big => {
      let reader : Reader = { bytes: self.bytes, format: self.format }
      for index in 0..<self.length {
        destination[index] = reader.read_u32_in_validated_range(
          self.data_offset + index * 4,
        )
      }
    }
  }
}

///|
/// Copies every element into caller-owned fixed-size storage. The view has
/// already validated the archived span. A destination that is too short is
/// left untouched so callers can safely reuse it after an error.
pub fn U32VecView::copy_into(
  self : U32VecView,
  destination : FixedArray[UInt],
) -> Unit raise RkyvError {
  let actual = destination.length()
  if actual < self.length {
    raise RkyvError::DestinationTooSmall(required=self.length, actual~)
  }
  self.copy_into_validated(destination)
}

///|
/// Decodes little-endian words four at a time before storing them through a
/// mutable view. MoonBit's native C FFI currently cannot accept the aggregate
/// `MutArrayView` argument, so this remains target-independent.
#warnings("-alert_experimental")
fn U32VecView::copy_little_endian_into_mut_view(
  self : U32VecView,
  destination : MutArrayView[UInt],
) -> Unit {
  let bytes = bytes_as_fixed_array(self.bytes)
  let reader : Reader = { bytes: self.bytes, format: self.format }
  let block_count = self.length / 4
  for block in 0..<block_count {
    let index = block * 4
    let lanes = @v128.v128_load(bytes, self.data_offset + index * 4)
    destination.unsafe_set(index, @v128.i32x4_extract_lane(lanes, 0))
    destination.unsafe_set(index + 1, @v128.i32x4_extract_lane(lanes, 1))
    destination.unsafe_set(index + 2, @v128.i32x4_extract_lane(lanes, 2))
    destination.unsafe_set(index + 3, @v128.i32x4_extract_lane(lanes, 3))
  }
  let tail_start = block_count * 4
  for index in tail_start..<self.length {
    destination.unsafe_set(
      index,
      reader.read_u32_in_validated_range(self.data_offset + index * 4),
    )
  }
}

///|
/// Copies every element into a caller-owned mutable array window. The window
/// can start at an arbitrary offset in either an `Array` or `FixedArray`; it
/// uses v128 loads and scalar stores rather than the native `FixedArray`
/// bulk-copy FFI.
pub fn U32VecView::copy_into_mut_view(
  self : U32VecView,
  destination : MutArrayView[UInt],
) -> Unit raise RkyvError {
  let actual = destination.length()
  if actual < self.length {
    raise RkyvError::DestinationTooSmall(required=self.length, actual~)
  }
  match self.format.endian {
    Endian::Little => self.copy_little_endian_into_mut_view(destination)
    Endian::Big => {
      let reader : Reader = { bytes: self.bytes, format: self.format }
      for index in 0..<self.length {
        destination.unsafe_set(
          index,
          reader.read_u32_in_validated_range(self.data_offset + index * 4),
        )
      }
    }
  }
}

///|
/// Decodes every element after validation into a fixed-size array. This avoids
/// the extra allocation and copy required to return a growable `Array`.
pub fn U32VecView::to_fixed_array_fast(self : U32VecView) -> FixedArray[UInt] {
  let storage : FixedArray[UInt] = FixedArray::make(self.length, 0U)
  self.copy_into_validated(storage)
  storage
}

///|
/// Decodes every element after `read_vec_u32` has validated the full element
/// span. Unlike the compatibility wrapper, this cannot fail.
#warnings("-alert_experimental")
pub fn U32VecView::to_array_fast(self : U32VecView) -> Array[UInt] {
  Array::from_fixed_array(self.to_fixed_array_fast())
}

///|
/// Decodes every element into a MoonBit array. Keep the `U32VecView` when a
/// caller only needs selected elements; use this at API boundaries that need
/// an owned collection.
pub fn U32VecView::to_array(self : U32VecView) -> Array[UInt] {
  self.to_array_fast()
}

///|
/// Resolves an `ArchivedOption<T>` tag into the offset of its present value.
/// The caller supplies the archived alignment of `T`; this keeps type-specific
/// layout in generated bindings while centralizing rkyv's tag/padding rule.
pub fn Reader::read_option_value_offset(
  self : Reader,
  offset : Int,
  value_alignment : Int,
) -> Int? raise RkyvError {
  if value_alignment <= 0 {
    raise RkyvError::InvalidAlignment(value_alignment)
  }
  let tag = self.read_u8(offset)
  if tag == b'\x00' {
    None
  } else {
    let after_tag = offset + 1
    let value_offset = (after_tag + value_alignment - 1) /
      value_alignment *
      value_alignment
    self.require(value_offset, 0)
    Some(value_offset)
  }
}

///|
/// Resolves an `ArchivedOption<T>` for an untrusted archive and rejects tags
/// other than rkyv's canonical `0` (`None`) and `1` (`Some`) values.
pub fn Reader::read_option_value_offset_strict(
  self : Reader,
  offset : Int,
  value_alignment : Int,
) -> Int? raise RkyvError {
  if value_alignment <= 0 {
    raise RkyvError::InvalidAlignment(value_alignment)
  }
  match self.read_u8(offset) {
    b'\x00' => None
    b'\x01' => {
      let after_tag = offset + 1
      let value_offset = (after_tag + value_alignment - 1) /
        value_alignment *
        value_alignment
      self.require(value_offset, 0)
      Some(value_offset)
    }
    value => raise RkyvError::InvalidOptionTag(value)
  }
}

///|
/// Decodes a valid UTF-8 subrange after checking its bounds.
fn Reader::read_text(
  self : Reader,
  offset : Int,
  length : Int,
) -> String raise RkyvError {
  let bytes = self.read_bytes_view(offset, length)
  @utf8.decode(bytes) catch {
    _ => raise RkyvError::InvalidUtf8
  }
}

///|
/// Decodes the marked length in an out-of-line `ArchivedString`.
fn Reader::read_out_of_line_string_length(
  self : Reader,
  offset : Int,
) -> Int raise RkyvError {
  match self.format.pointer_width {
    16 => {
      let value = self.read_u16(offset)
      (value & 0x3fU).reinterpret_as_int() +
      (value >> 8).reinterpret_as_int() * 64
    }
    32 => {
      let value = self.read_u32(offset)
      (value & 0x3fU).reinterpret_as_int() +
      (value >> 8).reinterpret_as_int() * 64
    }
    64 => raise RkyvError::InvalidPointerWidth(64)
    width => raise RkyvError::InvalidPointerWidth(width)
  }
}

///|
/// Reads rkyv 0.8's hybrid inline/out-of-line `ArchivedString` layout.
pub fn Reader::read_string(
  self : Reader,
  offset : Int,
) -> String raise RkyvError {
  let pointer_bytes = self.format.pointer_bytes()
  let inline_capacity = pointer_bytes * 2
  self.require(offset, inline_capacity)
  let first = self.bytes[offset].to_int()
  if (first & 0xc0) != 0x80 {
    let mut length = 0
    while length < inline_capacity && self.bytes[offset + length] != b'\xff' {
      length = length + 1
    }
    self.read_text(offset, length)
  } else {
    let length = self.read_out_of_line_string_length(offset)
    let relative = self.read_rel_ptr_offset(offset + pointer_bytes)
    self.read_text(offset + relative, length)
  }
}
