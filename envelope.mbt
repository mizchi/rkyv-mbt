///|
/// The self-identifying wrapper used when an archive crosses a trust boundary.
/// The contained payload is still a standard rkyv byte sequence: the wrapper
/// is optional and is never part of a Rust `Archived<T>` layout.
#valtype
pub struct ArchiveEnvelope {
  version : Int
  format : Format
  payload : Bytes
}

///| Returns the validated rkyv payload owned by this envelope.
pub fn ArchiveEnvelope::payload_bytes(self : ArchiveEnvelope) -> Bytes {
  self.payload
}

///| Returns the rkyv reader format declared by this envelope.
pub fn ArchiveEnvelope::archive_format(self : ArchiveEnvelope) -> Format {
  self.format
}

///|
/// Envelope errors are intentionally separate from `RkyvError`: callers can
/// reject a bad transport blob before attempting any schema-dependent reads.
pub suberror EnvelopeError {
  InvalidMagic
  UnsupportedVersion(Byte)
  UnsupportedFormat(Byte)
  InvalidLength(Int)
  PayloadLimitExceeded(actual~ : Int, limit~ : Int)
  ChecksumMismatch(expected~ : UInt, actual~ : UInt)
} derive(Debug, Eq)

///|
/// The current envelope protocol version.
pub let envelope_version : Byte = b'\x01'

///|
/// Number of bytes before the rkyv payload starts.
pub let envelope_header_size : Int = 16

///|
/// Computes the IEEE CRC-32 used by the envelope. This small table-free form
/// keeps the JavaScript runtime dependency-free and has negligible cost for
/// the small headers and metadata archives this package targets.
pub fn crc32(bytes : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for index in 0..<bytes.length() {
    crc = crc ^ bytes[index].to_uint()
    for _ in 0..<8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ 0xedb88320U
      } else {
        crc = crc >> 1
      }
    }
  }
  crc ^ 0xffffffffU
}

///|
/// Encodes rkyv's format settings into the v1 envelope flags byte.
fn envelope_format_flags(format : Format) -> Byte raise EnvelopeError {
  let pointer = match format.pointer_width {
    16 => 1U
    32 => 0U
    64 => 2U
    _ => raise EnvelopeError::UnsupportedFormat(b'\xff')
  }
  let endian = match format.endian {
    Endian::Little => 0U
    Endian::Big => 1U
  }
  let alignment = if format.aligned { 0U } else { 8U }
  (endian | (pointer << 1) | alignment).to_byte()
}

///|
/// Decodes the v1 envelope flags into rkyv reader settings.
fn envelope_format_from_flags(flags : Byte) -> Format raise EnvelopeError {
  let bits = flags.to_uint()
  if (bits & 0xf0U) != 0U {
    raise EnvelopeError::UnsupportedFormat(flags)
  }
  let pointer_width = match (bits >> 1) & 3U {
    0U => 32
    1U => 16
    2U => 64
    _ => raise EnvelopeError::UnsupportedFormat(flags)
  }
  let endian = if (bits & 1U) == 0U { Endian::Little } else { Endian::Big }
  Format::new(endian, pointer_width, (bits & 8U) == 0U)
}

///|
/// Writes a `u32` to an arbitrary output array in canonical little-endian.
fn envelope_append_u32(out : Array[Byte], value : UInt) -> Unit {
  out.push((value & 0xffU).to_byte())
  out.push(((value >> 8) & 0xffU).to_byte())
  out.push(((value >> 16) & 0xffU).to_byte())
  out.push(((value >> 24) & 0xffU).to_byte())
}

///|
/// Wraps a default-format rkyv payload in the versioned envelope. Use
/// `encode_envelope_with_format` when Rust was built with a non-default rkyv
/// format feature.
pub fn encode_envelope(payload : Bytes) -> Bytes {
  encode_envelope_with_format(payload, default_format()) catch {
    _ => abort("the default rkyv format must be representable in an envelope")
  }
}

///|
/// Wraps an rkyv payload with its exact reader format. The payload is copied
/// once so the returned value is a standalone transport buffer.
pub fn encode_envelope_with_format(
  payload : Bytes,
  format : Format,
) -> Bytes raise EnvelopeError {
  let length = payload.length()
  if length < 0 || length > 0x7fff_ffff {
    raise EnvelopeError::InvalidLength(length)
  }
  let flags = envelope_format_flags(format)
  let out : Array[Byte] = [
    b'R', b'M', b'B', b'T', envelope_version, flags, b'\x00', b'\x00',
  ]
  envelope_append_u32(out, length.reinterpret_as_uint())
  envelope_append_u32(out, crc32(payload))
  for index in 0..<length {
    out.push(payload[index])
  }
  Bytes::from_array(out)
}

///|
/// Parses and checks a v1 envelope before returning a standalone rkyv
/// payload. Applications should pass `decoded.archive_format()` to
/// `Reader::with_format` when the producer may select non-default rkyv format
/// features.
pub fn decode_envelope(bytes : Bytes) -> ArchiveEnvelope raise EnvelopeError {
  decode_envelope_with_limit(bytes, 0x7fff_ffff)
}

///|
/// Parses an envelope while enforcing a caller-provided payload ceiling before
/// copying any payload bytes. Use this at network and storage boundaries to
/// keep malformed length headers from causing unbounded allocation.
pub fn decode_envelope_with_limit(
  bytes : Bytes,
  max_payload_length : Int,
) -> ArchiveEnvelope raise EnvelopeError {
  if max_payload_length < 0 {
    raise EnvelopeError::PayloadLimitExceeded(
      actual=0,
      limit=max_payload_length,
    )
  }
  if bytes.length() < envelope_header_size {
    raise EnvelopeError::InvalidLength(bytes.length())
  }
  if bytes[0] != b'R' ||
    bytes[1] != b'M' ||
    bytes[2] != b'B' ||
    bytes[3] != b'T' {
    raise EnvelopeError::InvalidMagic
  }
  if bytes[4] != envelope_version {
    raise EnvelopeError::UnsupportedVersion(bytes[4])
  }
  let format = envelope_format_from_flags(bytes[5])
  if bytes[6] != b'\x00' || bytes[7] != b'\x00' {
    raise EnvelopeError::UnsupportedFormat(bytes[5])
  }
  let declared_length = bytes[8].to_uint() |
    (bytes[9].to_uint() << 8) |
    (bytes[10].to_uint() << 16) |
    (bytes[11].to_uint() << 24)
  if declared_length > 0x7fff_ffffU {
    raise EnvelopeError::InvalidLength(declared_length.reinterpret_as_int())
  }
  let payload_length = declared_length.reinterpret_as_int()
  if payload_length != bytes.length() - envelope_header_size {
    raise EnvelopeError::InvalidLength(payload_length)
  }
  if payload_length > max_payload_length {
    raise EnvelopeError::PayloadLimitExceeded(
      actual=payload_length,
      limit=max_payload_length,
    )
  }
  let expected = bytes[12].to_uint() |
    (bytes[13].to_uint() << 8) |
    (bytes[14].to_uint() << 16) |
    (bytes[15].to_uint() << 24)
  let payload_bytes : Array[Byte] = []
  for index in 0..<payload_length {
    payload_bytes.push(bytes[envelope_header_size + index])
  }
  let payload = Bytes::from_array(payload_bytes)
  let actual = crc32(payload)
  if expected != actual {
    raise EnvelopeError::ChecksumMismatch(expected~, actual~)
  }
  { version: envelope_version.to_int(), format, payload }
}
