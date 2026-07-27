///|
/// Byte order used by an rkyv archive.
pub enum Endian {
  Little
  Big
} derive(Debug, Eq)

///|
/// rkyv wire-format settings. The default is rkyv's standard aligned,
/// little-endian, 32-bit-pointer format.
pub struct Format {
  endian : Endian
  pointer_width : Int
  aligned : Bool
} derive(Debug, Eq)

///|
/// Errors returned while safely reading an archive. This reader deliberately
/// checks bounds, unlike rkyv's `access_unchecked` APIs.
pub suberror RkyvError {
  OutOfBounds(offset~ : Int, size~ : Int, length~ : Int)
  InvalidPointerWidth(Int)
  InvalidAlignment(Int)
  InvalidRelativePointer(Int)
  LengthOverflow(Int)
  InvalidCollectionLength(Int)
  InvalidElementSize(Int)
  DestinationTooSmall(required~ : Int, actual~ : Int)
  InvalidUtf8
} derive(Debug, Eq)

///|
/// Returns the format used by rkyv when no format feature is enabled.
pub fn default_format() -> Format {
  { endian: Endian::Little, pointer_width: 32, aligned: true }
}

///|
/// Creates a format explicitly. Use this when matching non-default rkyv
/// feature flags in a Rust producer.
pub fn Format::new(
  endian : Endian,
  pointer_width : Int,
  aligned : Bool,
) -> Format {
  { endian, pointer_width, aligned }
}

///|
/// Creates a big-endian rkyv format.
pub fn Format::big_endian(pointer_width : Int, aligned : Bool) -> Format {
  { endian: Endian::Big, pointer_width, aligned }
}

///|
/// Returns the size of archived pointers and `usize` values in bytes.
pub fn Format::pointer_bytes(self : Format) -> Result[Int, RkyvError] {
  match self.pointer_width {
    16 => Ok(2)
    32 => Ok(4)
    64 => Ok(8)
    width => Err(RkyvError::InvalidPointerWidth(width))
  }
}
