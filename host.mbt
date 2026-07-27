///|
/// A MoonBit-owned schema for the rkyv 0.8 default archive profile. It is a
/// small, explicit host-side alternative to the Rust layout derive: schema
/// field order is the archive layout contract.
pub(all) enum Schema {
  U32
  Bool
  String
  VecU32
  Struct(Array[Field])
}

///|
/// A named field in a host-defined archived struct.
pub(all) struct Field {
  name : String
  schema : Schema
}

///|
/// A dynamic value accepted by a `Schema` encoder.
pub(all) enum Value {
  U32(UInt)
  Bool(Bool)
  String(String)
  VecU32(Array[UInt])
  Struct(Array[ValueField])
}

///|
/// A named field value. Names make accidental schema/value ordering mistakes
/// fail before any root archive object is written.
pub(all) struct ValueField {
  name : String
  value : Value
}

///|
/// Errors raised by the host schema encoder before it emits an invalid archive.
pub(all) suberror SchemaError {
  TypeMismatch(expected~ : String)
  FieldCountMismatch(expected~ : Int, actual~ : Int)
  FieldMismatch(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
/// A schema-directed, zero-copy view over a host-defined archived value.
/// Field lookup stays dynamic because the schema is a MoonBit value rather than
/// source generated from Rust's compiler layout.
pub struct View {
  schema : Schema
  reader : Reader
  offset : Int
}

///|
/// A schema-directed mutable view over a caller-owned archive buffer. It can
/// update only fixed-width fields, so no relative pointer or collection length
/// can become invalid.
pub struct MutView {
  schema : Schema
  bytes : MutArrayView[Byte]
  offset : Int
}

///|
/// A mutable view of an existing `ArchivedVec<u32>`. It can replace elements
/// in place, but cannot change the vector length or move its data.
pub struct MutU32VecView {
  bytes : MutArrayView[Byte]
  data_offset : Int
  length : Int
}

///|
/// The size and alignment of one archived value under the default rkyv
/// profile. Struct offsets are retained so nested values can be written in one
/// contiguous root representation after their dependencies have been emitted.
priv struct SchemaLayout {
  size : Int
  alignment : Int
  field_offsets : Array[Int]
}

///|
/// An encoder-ready value. Out-of-line dependencies are emitted during
/// preparation, before the enclosing root representation is allocated.
priv enum PreparedValue {
  U32(UInt)
  Bool(Bool)
  InlineString(Bytes)
  OutOfLineString(Int, Int)
  VecU32(Array[UInt], Int)
  Struct(Array[PreparedValue])
}

///|
/// Rounds an offset up to an archive alignment boundary.
fn schema_align_up(offset : Int, alignment : Int) -> Int {
  if alignment <= 1 {
    offset
  } else {
    (offset + alignment - 1) / alignment * alignment
  }
}

///|
/// Computes the host-declared archived layout. This deliberately follows the
/// declaration order rather than attempting to reproduce Rust's unspecified
/// `repr(Rust)` field reordering.
fn Schema::layout(self : Schema) -> SchemaLayout {
  match self {
    Schema::U32 => { size: 4, alignment: 4, field_offsets: [] }
    Schema::Bool => { size: 1, alignment: 1, field_offsets: [] }
    Schema::String => { size: 8, alignment: 4, field_offsets: [] }
    Schema::VecU32 => { size: 8, alignment: 4, field_offsets: [] }
    Schema::Struct(fields) => {
      let mut size = 0
      let mut alignment = 1
      let offsets : Array[Int] = []
      for field in fields {
        let field_layout = field.schema.layout()
        size = schema_align_up(size, field_layout.alignment)
        offsets.push(size)
        size = size + field_layout.size
        if field_layout.alignment > alignment {
          alignment = field_layout.alignment
        }
      }
      {
        size: schema_align_up(size, alignment),
        alignment,
        field_offsets: offsets,
      }
    }
  }
}

///|
/// Writes zero bytes for archive padding or for an inline struct allocation.
fn schema_append_zeroes(out : Array[Byte], count : Int) -> Unit {
  for _ in 0..<count {
    out.push(b'\x00')
  }
}

///|
/// Writes a little-endian u32 into an already allocated archive span.
fn schema_write_u32_le(out : Array[Byte], offset : Int, value : UInt) -> Unit {
  out[offset] = (value & 0xffU).to_byte()
  out[offset + 1] = ((value >> 8) & 0xffU).to_byte()
  out[offset + 2] = ((value >> 16) & 0xffU).to_byte()
  out[offset + 3] = ((value >> 24) & 0xffU).to_byte()
}

///|
/// Writes a little-endian `u32` into a caller-owned mutable archive buffer.
fn schema_write_mut_u32_le(
  out : MutArrayView[Byte],
  offset : Int,
  value : UInt,
) -> Unit {
  out[offset] = (value & 0xffU).to_byte()
  out[offset + 1] = ((value >> 8) & 0xffU).to_byte()
  out[offset + 2] = ((value >> 16) & 0xffU).to_byte()
  out[offset + 3] = ((value >> 24) & 0xffU).to_byte()
}

///|
/// Writes a relative pointer using rkyv's little-endian i32 representation.
fn schema_write_rel_ptr(out : Array[Byte], offset : Int, target : Int) -> Unit {
  schema_write_u32_le(out, offset, (target - offset).reinterpret_as_uint())
}

///|
/// Emits dependencies recursively and returns the representation that will be
/// placed inside the final root object.
fn Schema::prepare(
  self : Schema,
  value : Value,
  out : Array[Byte],
) -> PreparedValue raise SchemaError {
  match self {
    Schema::U32 =>
      match value {
        Value::U32(value) => PreparedValue::U32(value)
        _ => raise SchemaError::TypeMismatch(expected="u32")
      }
    Schema::Bool =>
      match value {
        Value::Bool(value) => PreparedValue::Bool(value)
        _ => raise SchemaError::TypeMismatch(expected="bool")
      }
    Schema::String =>
      match value {
        Value::String(value) => {
          let bytes = @utf8.encode(value)
          let length = bytes.length()
          if length <= 8 {
            PreparedValue::InlineString(bytes)
          } else {
            pad_to(out, 4)
            let data_offset = out.length()
            for index in 0..<length {
              out.push(bytes[index])
            }
            PreparedValue::OutOfLineString(length, data_offset)
          }
        }
        _ => raise SchemaError::TypeMismatch(expected="String")
      }
    Schema::VecU32 =>
      match value {
        Value::VecU32(values) => {
          pad_to(out, 4)
          let data_offset = out.length()
          for value in values {
            append_u32_le(out, value)
          }
          PreparedValue::VecU32(values, data_offset)
        }
        _ => raise SchemaError::TypeMismatch(expected="Vec<u32>")
      }
    Schema::Struct(fields) =>
      match value {
        Value::Struct(values) => {
          let expected = fields.length()
          let actual = values.length()
          if expected != actual {
            raise SchemaError::FieldCountMismatch(expected~, actual~)
          }
          let prepared : Array[PreparedValue] = []
          for index in 0..<expected {
            let field = fields[index]
            let field_value = values[index]
            if field.name != field_value.name {
              raise SchemaError::FieldMismatch(
                expected=field.name,
                actual=field_value.name,
              )
            }
            prepared.push(field.schema.prepare(field_value.value, out))
          }
          PreparedValue::Struct(prepared)
        }
        _ => raise SchemaError::TypeMismatch(expected="struct")
      }
  }
}

///|
/// Fills one already allocated inline representation. The schema and prepared
/// value always originate from the same `prepare` call.
fn Schema::write_prepared(
  self : Schema,
  prepared : PreparedValue,
  out : Array[Byte],
  offset : Int,
) -> Unit {
  match self {
    Schema::U32 =>
      match prepared {
        PreparedValue::U32(value) => schema_write_u32_le(out, offset, value)
        _ => abort("host schema and prepared value diverged")
      }
    Schema::Bool =>
      match prepared {
        PreparedValue::Bool(value) =>
          if value {
            out[offset] = b'\x01'
          } else {
            out[offset] = b'\x00'
          }
        _ => abort("host schema and prepared value diverged")
      }
    Schema::String =>
      match prepared {
        PreparedValue::InlineString(bytes) => {
          for index in 0..<8 {
            out[offset + index] = b'\xff'
          }
          for index in 0..<bytes.length() {
            out[offset + index] = bytes[index]
          }
        }
        PreparedValue::OutOfLineString(length, data_offset) => {
          let low_six_bits = length % 64
          let encoded_length = low_six_bits.reinterpret_as_uint() |
            0x80U |
            ((length - low_six_bits).reinterpret_as_uint() << 2)
          schema_write_u32_le(out, offset, encoded_length)
          schema_write_u32_le(
            out,
            offset + 4,
            (data_offset - offset).reinterpret_as_uint(),
          )
        }
        _ => abort("host schema and prepared value diverged")
      }
    Schema::VecU32 =>
      match prepared {
        PreparedValue::VecU32(values, data_offset) => {
          schema_write_rel_ptr(out, offset, data_offset)
          schema_write_u32_le(
            out,
            offset + 4,
            values.length().reinterpret_as_uint(),
          )
        }
        _ => abort("host schema and prepared value diverged")
      }
    Schema::Struct(fields) =>
      match prepared {
        PreparedValue::Struct(values) => {
          let layout = self.layout()
          for index in 0..<fields.length() {
            fields[index].schema.write_prepared(
              values[index],
              out,
              offset + layout.field_offsets[index],
            )
          }
        }
        _ => abort("host schema and prepared value diverged")
      }
  }
}

///|
/// Encodes a host-defined value into a caller-owned mutable rkyv archive. This
/// function is target-independent, so `moon build --target js` produces the
/// same bytes without Rust.
pub fn Schema::encode_mut(
  self : Schema,
  value : Value,
) -> Array[Byte] raise SchemaError {
  let out : Array[Byte] = []
  let prepared = self.prepare(value, out)
  let layout = self.layout()
  pad_to(out, layout.alignment)
  let root_offset = out.length()
  schema_append_zeroes(out, layout.size)
  self.write_prepared(prepared, out, root_offset)
  out
}

///|
/// Encodes a value into an immutable rkyv archive. Use `encode_mut` when the
/// caller intends to apply later fixed-width in-place updates.
pub fn Schema::encode(self : Schema, value : Value) -> Bytes raise SchemaError {
  Bytes::from_array(self.encode_mut(value))
}

///|
/// Opens the root representation described by this host schema. The complete
/// inline span is validated immediately; out-of-line values are validated by
/// their respective reader accessors.
pub fn Schema::root(self : Schema, bytes : Bytes) -> View raise RkyvError {
  let reader = Reader::new(bytes)
  let layout = self.layout()
  let offset = reader.root_offset(layout.size)
  { schema: self, reader, offset }
}

///|
/// Opens a mutable root over caller-owned archive bytes. The inline root span
/// is validated before the view is returned; collection fields are additionally
/// validated when `vec_u32_mut` is requested.
pub fn Schema::root_mut(
  self : Schema,
  bytes : MutArrayView[Byte],
) -> MutView raise RkyvError {
  let reader = Reader::new(Bytes::from_array(bytes.view()))
  let layout = self.layout()
  let offset = reader.root_offset(layout.size)
  { schema: self, bytes, offset }
}

///|
/// Returns a nested struct field by name. `None` means this view is not a
/// struct or that the requested field does not exist in its host schema.
pub fn View::field(self : View, name : String) -> View? {
  match self.schema {
    Schema::Struct(fields) => {
      let layout = self.schema.layout()
      let mut found = None
      for index in 0..<fields.length() {
        let field = fields[index]
        if field.name == name {
          found = Some({
            schema: field.schema,
            reader: self.reader,
            offset: self.offset + layout.field_offsets[index],
          })
        }
      }
      found
    }
    _ => None
  }
}

///|
/// Returns a nested mutable struct field by name. `None` means this view is
/// not a struct or that the requested field does not exist.
pub fn MutView::field(self : MutView, name : String) -> MutView? {
  match self.schema {
    Schema::Struct(fields) => {
      let layout = self.schema.layout()
      let mut found = None
      for index in 0..<fields.length() {
        let field = fields[index]
        if field.name == name {
          found = Some({
            schema: field.schema,
            bytes: self.bytes,
            offset: self.offset + layout.field_offsets[index],
          })
        }
      }
      found
    }
    _ => None
  }
}

///|
/// Replaces a `u32` field in place. Returns `false` if this view's schema is
/// not `Schema::U32`.
pub fn MutView::set_u32(self : MutView, value : UInt) -> Bool {
  match self.schema {
    Schema::U32 => {
      schema_write_mut_u32_le(self.bytes, self.offset, value)
      true
    }
    _ => false
  }
}

///|
/// Replaces a boolean field in place. Returns `false` if this view's schema is
/// not `Schema::Bool`.
pub fn MutView::set_bool(self : MutView, value : Bool) -> Bool {
  match self.schema {
    Schema::Bool => {
      self.bytes[self.offset] = if value { b'\x01' } else { b'\x00' }
      true
    }
    _ => false
  }
}

///|
/// Replaces a string only when its UTF-8 byte length is unchanged. The archive
/// representation, relative pointer, and inline/out-of-line choice therefore
/// remain valid. Returns `false` for a different-length string or a non-string
/// schema; malformed archived strings raise `RkyvError` before any write.
pub fn MutView::set_string(
  self : MutView,
  value : String,
) -> Bool raise RkyvError {
  match self.schema {
    Schema::String => {
      let snapshot = Bytes::from_array(self.bytes.view())
      let reader = Reader::new(snapshot)
      let current = reader.read_string(self.offset)
      let replacement = @utf8.encode(value)
      if replacement.length() != @utf8.encode(current).length() {
        false
      } else {
        let first = self.bytes[self.offset].to_int()
        let data_offset = if (first & 0xc0) != 0x80 {
          self.offset
        } else {
          self.offset + reader.read_rel_ptr_offset(self.offset + 4)
        }
        for index in 0..<replacement.length() {
          self.bytes[data_offset + index] = replacement[index]
        }
        true
      }
    }
    _ => false
  }
}

///|
/// Opens a mutable view of an existing `Vec<u32>`. The header and full element
/// span are checked before returning the view. The snapshot used for validation
/// is discarded; writes always target the caller-owned mutable buffer.
pub fn MutView::vec_u32_mut(self : MutView) -> MutU32VecView? raise RkyvError {
  match self.schema {
    Schema::VecU32 => {
      let reader = Reader::new(Bytes::from_array(self.bytes.view()))
      let view = reader.read_vec_u32(self.offset)
      Some({
        bytes: self.bytes,
        data_offset: view.data_offset,
        length: view.length,
      })
    }
    _ => None
  }
}

///|
/// Returns the fixed archived element count of this mutable vector view.
pub fn MutU32VecView::length(self : MutU32VecView) -> Int {
  self.length
}

///|
/// Replaces one existing vector element in place. Returns `false` for an
/// out-of-range index; this API never resizes or relocates the vector.
pub fn MutU32VecView::set(
  self : MutU32VecView,
  index : Int,
  value : UInt,
) -> Bool {
  if index < 0 || index >= self.length {
    false
  } else {
    schema_write_mut_u32_le(self.bytes, self.data_offset + index * 4, value)
    true
  }
}

///|
/// Reads a `u32` when this view's schema is `Schema::U32`.
pub fn View::read_u32(self : View) -> UInt? raise RkyvError {
  match self.schema {
    Schema::U32 => Some(self.reader.read_u32(self.offset))
    _ => None
  }
}

///|
/// Reads a boolean when this view's schema is `Schema::Bool`.
pub fn View::read_bool(self : View) -> Bool? raise RkyvError {
  match self.schema {
    Schema::Bool => Some(self.reader.read_bool(self.offset))
    _ => None
  }
}

///|
/// Reads a string when this view's schema is `Schema::String`.
pub fn View::read_string(self : View) -> String? raise RkyvError {
  match self.schema {
    Schema::String => Some(self.reader.read_string(self.offset))
    _ => None
  }
}

///|
/// Opens a zero-copy `ArchivedVec<u32>` view when this schema declares one.
pub fn View::read_vec_u32(self : View) -> U32VecView? raise RkyvError {
  match self.schema {
    Schema::VecU32 => Some(self.reader.read_vec_u32(self.offset))
    _ => None
  }
}
