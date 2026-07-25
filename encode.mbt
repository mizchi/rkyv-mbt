///|
/// Appends one little-endian `u32` to an archive under construction.
fn append_u32_le(out : Array[Byte], value : UInt) -> Unit {
  out.push((value & 0xffU).to_byte())
  out.push(((value >> 8) & 0xffU).to_byte())
  out.push(((value >> 16) & 0xffU).to_byte())
  out.push(((value >> 24) & 0xffU).to_byte())
}

///|
/// Appends one little-endian `i32` by preserving its two's-complement bits.
fn append_i32_le(out : Array[Byte], value : Int) -> Unit {
  append_u32_le(out, value.reinterpret_as_uint())
}

///|
/// Pads an archive to an alignment boundary using rkyv's zero padding.
fn pad_to(out : Array[Byte], alignment : Int) -> Unit {
  while out.length() % alignment != 0 {
    out.push(b'\x00')
  }
}

///|
/// Encodes a root `Vec<u32>` in rkyv's default format. The element data is
/// emitted before the `ArchivedVec` root header, as required by rkyv.
pub fn encode_vec_u32(values : Array[UInt]) -> Bytes {
  let out : Array[Byte] = []
  for value in values {
    append_u32_le(out, value)
  }
  pad_to(out, 4)
  let header_offset = out.length()
  append_i32_le(out, -header_offset)
  append_u32_le(out, values.length().reinterpret_as_uint())
  Bytes::from_array(out)
}

///|
/// Encodes a root `String` in rkyv 0.8's default format. Strings up to eight
/// UTF-8 bytes are inline; longer strings are written before their root repr.
pub fn encode_string(value : String) -> Bytes {
  let encoded = @utf8.encode(value)
  let length = encoded.length()
  let out : Array[Byte] = []
  if length <= 8 {
    for index in 0..<length {
      out.push(encoded[index])
    }
    while out.length() < 8 {
      out.push(b'\xff')
    }
    return Bytes::from_array(out)
  }

  for index in 0..<length {
    out.push(encoded[index])
  }
  pad_to(out, 4)
  let repr_offset = out.length()
  let low_six_bits = length % 64
  let encoded_length = low_six_bits.reinterpret_as_uint() |
    0x80U |
    ((length - low_six_bits).reinterpret_as_uint() << 2)
  append_u32_le(out, encoded_length)
  append_i32_le(out, -repr_offset)
  Bytes::from_array(out)
}
