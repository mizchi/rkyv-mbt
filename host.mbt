///|
/// A MoonBit-owned schema for the rkyv 0.8 default archive profile. It is a
/// small, explicit host-side alternative to the Rust layout derive. `Struct`
/// uses field order as its contract; generated Rust writers use `StructLayout`
/// with compiler-provided offsets and archived size instead.
pub(all) enum Schema {
  U8
  U16
  U32
  U64
  I8
  I16
  I32
  I64
  F32
  F64
  Bool
  String
  VecU32
  Vec(Schema)
  Option(Schema)
  Struct(Array[Field])
  StructLayout(Array[Field], Array[Int], Int)
  TaggedUnion(Array[Variant], Int, Int, Int)
}

///|
/// A named field in a host-defined archived struct.
pub(all) struct Field {
  name : String
  schema : Schema
}

///|
/// One variant in a host-defined `#[repr(u8)]` archived enum. `tag_offset`,
/// `payload_offset`, and `archived_size` are supplied by `TaggedUnion`, so the
/// union's native Rust layout is always an explicit part of the contract.
pub(all) struct Variant {
  name : String
  tag : Byte
  schema : Schema
}

///|
/// A dynamic value accepted by a `Schema` encoder.
pub(all) enum Value {
  U8(Byte)
  U16(UInt)
  U32(UInt)
  U64(UInt64)
  I8(Int)
  I16(Int)
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  Bool(Bool)
  String(String)
  VecU32(Array[UInt])
  Vec(Array[Value])
  Option(Value?)
  Struct(Array[ValueField])
  Tagged(Byte, Value?)
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
  U8(Byte)
  U16(UInt)
  U32(UInt)
  U64(UInt64)
  I8(Int)
  I16(Int)
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
  Bool(Bool)
  InlineString(Bytes)
  OutOfLineString(Int, Int)
  VecU32(Array[UInt], Int)
  Vec(Array[PreparedValue], Int)
  Option(PreparedValue?)
  Struct(Array[PreparedValue])
  Tagged(Byte, PreparedValue?)
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
/// Computes the host-declared archived layout. `Struct` follows declaration
/// order, while `StructLayout` retains the exact offsets and archived size
/// supplied by Rust layout code generation.
fn Schema::layout(self : Schema) -> SchemaLayout {
  match self {
    Schema::U8 | Schema::I8 | Schema::Bool =>
      { size: 1, alignment: 1, field_offsets: [] }
    Schema::U16 | Schema::I16 => { size: 2, alignment: 2, field_offsets: [] }
    Schema::U32 => { size: 4, alignment: 4, field_offsets: [] }
    Schema::I32 | Schema::F32 => { size: 4, alignment: 4, field_offsets: [] }
    Schema::U64 | Schema::I64 | Schema::F64 =>
      { size: 8, alignment: 8, field_offsets: [] }
    Schema::String => { size: 8, alignment: 4, field_offsets: [] }
    Schema::VecU32 => { size: 8, alignment: 4, field_offsets: [] }
    Schema::Vec(_) => { size: 8, alignment: 4, field_offsets: [] }
    Schema::Option(value_schema) => {
      let value_layout = value_schema.layout()
      let value_offset = schema_align_up(1, value_layout.alignment)
      {
        size: schema_align_up(
          value_offset + value_layout.size,
          value_layout.alignment,
        ),
        alignment: value_layout.alignment,
        field_offsets: [],
      }
    }
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
    Schema::StructLayout(fields, offsets, archived_size) => {
      if fields.length() != offsets.length() {
        abort(
          "explicit host struct layout has a different field and offset count",
        )
      }
      if archived_size < 0 {
        abort("explicit host struct layout has a negative archived size")
      }
      let mut alignment = 1
      for index in 0..<fields.length() {
        let field_layout = fields[index].schema.layout()
        let offset = offsets[index]
        if offset < 0 || offset + field_layout.size > archived_size {
          abort("explicit host struct field does not fit in its archived size")
        }
        if field_layout.alignment > alignment {
          alignment = field_layout.alignment
        }
      }
      { size: archived_size, alignment, field_offsets: offsets }
    }
    Schema::TaggedUnion(variants, tag_offset, payload_offset, archived_size) => {
      if tag_offset < 0 ||
        tag_offset >= archived_size ||
        payload_offset < 0 ||
        archived_size < 0 {
        abort("invalid explicit tagged union layout")
      }
      let mut alignment = 1
      for variant in variants {
        let payload_layout = variant.schema.layout()
        if payload_offset + payload_layout.size > archived_size {
          abort(
            "explicit tagged union payload does not fit in its archived size",
          )
        }
        if payload_layout.alignment > alignment {
          alignment = payload_layout.alignment
        }
      }
      { size: archived_size, alignment, field_offsets: [] }
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
/// Writes a little-endian `u16` into an already allocated archive span.
fn schema_write_u16_le(out : Array[Byte], offset : Int, value : UInt) -> Unit {
  out[offset] = (value & 0xffU).to_byte()
  out[offset + 1] = ((value >> 8) & 0xffU).to_byte()
}

///|
/// Writes a little-endian `u64` into an already allocated archive span.
fn schema_write_u64_le(out : Array[Byte], offset : Int, value : UInt64) -> Unit {
  for index in 0..<8 {
    out[offset + index] = ((value >> (index * 8)) & 0xffUL).to_byte()
  }
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
    Schema::U8 =>
      match value {
        Value::U8(value) => PreparedValue::U8(value)
        _ => raise SchemaError::TypeMismatch(expected="u8")
      }
    Schema::U16 =>
      match value {
        Value::U16(value) => PreparedValue::U16(value)
        _ => raise SchemaError::TypeMismatch(expected="u16")
      }
    Schema::U32 =>
      match value {
        Value::U32(value) => PreparedValue::U32(value)
        _ => raise SchemaError::TypeMismatch(expected="u32")
      }
    Schema::U64 =>
      match value {
        Value::U64(value) => PreparedValue::U64(value)
        _ => raise SchemaError::TypeMismatch(expected="u64")
      }
    Schema::I8 =>
      match value {
        Value::I8(value) => PreparedValue::I8(value)
        _ => raise SchemaError::TypeMismatch(expected="i8")
      }
    Schema::I16 =>
      match value {
        Value::I16(value) => PreparedValue::I16(value)
        _ => raise SchemaError::TypeMismatch(expected="i16")
      }
    Schema::I32 =>
      match value {
        Value::I32(value) => PreparedValue::I32(value)
        _ => raise SchemaError::TypeMismatch(expected="i32")
      }
    Schema::I64 =>
      match value {
        Value::I64(value) => PreparedValue::I64(value)
        _ => raise SchemaError::TypeMismatch(expected="i64")
      }
    Schema::F32 =>
      match value {
        Value::F32(value) => PreparedValue::F32(value)
        _ => raise SchemaError::TypeMismatch(expected="f32")
      }
    Schema::F64 =>
      match value {
        Value::F64(value) => PreparedValue::F64(value)
        _ => raise SchemaError::TypeMismatch(expected="f64")
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
    Schema::Vec(element_schema) =>
      match value {
        Value::Vec(values) => {
          let prepared : Array[PreparedValue] = []
          for value in values {
            prepared.push(element_schema.prepare(value, out))
          }
          let element_layout = element_schema.layout()
          pad_to(out, element_layout.alignment)
          let data_offset = out.length()
          schema_append_zeroes(out, element_layout.size * prepared.length())
          PreparedValue::Vec(prepared, data_offset)
        }
        _ => raise SchemaError::TypeMismatch(expected="Vec<T>")
      }
    Schema::Option(value_schema) =>
      match value {
        Value::Option(None) => PreparedValue::Option(None)
        Value::Option(Some(value)) =>
          PreparedValue::Option(Some(value_schema.prepare(value, out)))
        _ => raise SchemaError::TypeMismatch(expected="Option<T>")
      }
    Schema::Struct(fields) | Schema::StructLayout(fields, _, _) =>
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
    Schema::TaggedUnion(variants, _, _, _) =>
      match value {
        Value::Tagged(tag, payload) => {
          let mut found : Variant? = None
          for variant in variants {
            if variant.tag == tag {
              found = Some(variant)
            }
          }
          match found {
            None =>
              raise SchemaError::TypeMismatch(
                expected="known tagged union variant",
              )
            Some(variant) =>
              match payload {
                None =>
                  if variant.schema.layout().size == 0 {
                    PreparedValue::Tagged(tag, None)
                  } else {
                    raise SchemaError::TypeMismatch(
                      expected="tagged union payload",
                    )
                  }
                Some(payload) =>
                  PreparedValue::Tagged(
                    tag,
                    Some(variant.schema.prepare(payload, out)),
                  )
              }
          }
        }
        _ => raise SchemaError::TypeMismatch(expected="tagged union")
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
    Schema::U8 =>
      match prepared {
        PreparedValue::U8(value) => out[offset] = value
        _ => abort("host schema and prepared value diverged")
      }
    Schema::U16 =>
      match prepared {
        PreparedValue::U16(value) => schema_write_u16_le(out, offset, value)
        _ => abort("host schema and prepared value diverged")
      }
    Schema::U32 =>
      match prepared {
        PreparedValue::U32(value) => schema_write_u32_le(out, offset, value)
        _ => abort("host schema and prepared value diverged")
      }
    Schema::U64 =>
      match prepared {
        PreparedValue::U64(value) => schema_write_u64_le(out, offset, value)
        _ => abort("host schema and prepared value diverged")
      }
    Schema::I8 =>
      match prepared {
        PreparedValue::I8(value) =>
          out[offset] = value.reinterpret_as_uint().to_byte()
        _ => abort("host schema and prepared value diverged")
      }
    Schema::I16 =>
      match prepared {
        PreparedValue::I16(value) =>
          schema_write_u16_le(out, offset, value.reinterpret_as_uint())
        _ => abort("host schema and prepared value diverged")
      }
    Schema::I32 =>
      match prepared {
        PreparedValue::I32(value) =>
          schema_write_u32_le(out, offset, value.reinterpret_as_uint())
        _ => abort("host schema and prepared value diverged")
      }
    Schema::I64 =>
      match prepared {
        PreparedValue::I64(value) =>
          schema_write_u64_le(out, offset, value.reinterpret_as_uint64())
        _ => abort("host schema and prepared value diverged")
      }
    Schema::F32 =>
      match prepared {
        PreparedValue::F32(value) =>
          schema_write_u32_le(out, offset, value.reinterpret_as_uint())
        _ => abort("host schema and prepared value diverged")
      }
    Schema::F64 =>
      match prepared {
        PreparedValue::F64(value) =>
          schema_write_u64_le(out, offset, value.reinterpret_as_uint64())
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
    Schema::Vec(element_schema) =>
      match prepared {
        PreparedValue::Vec(values, data_offset) => {
          schema_write_rel_ptr(out, offset, data_offset)
          schema_write_u32_le(
            out,
            offset + 4,
            values.length().reinterpret_as_uint(),
          )
          let element_layout = element_schema.layout()
          for index in 0..<values.length() {
            element_schema.write_prepared(
              values[index],
              out,
              data_offset + index * element_layout.size,
            )
          }
        }
        _ => abort("host schema and prepared value diverged")
      }
    Schema::Option(value_schema) =>
      match prepared {
        PreparedValue::Option(None) => out[offset] = b'\x00'
        PreparedValue::Option(Some(value)) => {
          out[offset] = b'\x01'
          let value_offset = schema_align_up(1, value_schema.layout().alignment)
          value_schema.write_prepared(value, out, offset + value_offset)
        }
        _ => abort("host schema and prepared value diverged")
      }
    Schema::Struct(fields) | Schema::StructLayout(fields, _, _) =>
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
    Schema::TaggedUnion(variants, tag_offset, payload_offset, _) =>
      match prepared {
        PreparedValue::Tagged(tag, payload) => {
          out[offset + tag_offset] = tag
          match payload {
            None => ()
            Some(payload) => {
              let mut found : Variant? = None
              for variant in variants {
                if variant.tag == tag {
                  found = Some(variant)
                }
              }
              match found {
                None => abort("prepared tagged union has an unknown tag")
                Some(variant) =>
                  variant.schema.write_prepared(
                    payload,
                    out,
                    offset + payload_offset,
                  )
              }
            }
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
/// Fully validates a host-defined archive before it is exposed to an
/// application. This checks every reachable relative pointer, string, vector
/// extent, option tag, boolean discriminant, and tagged-union discriminant.
pub fn Schema::validate(self : Schema, bytes : Bytes) -> Unit raise RkyvError {
  let root = self.root(bytes)
  self.validate_at(root.reader, root.offset, 256)
}

///|
/// Validates one value at a known in-range inline archive offset.
fn Schema::validate_at(
  self : Schema,
  reader : Reader,
  offset : Int,
  remaining_depth : Int,
) -> Unit raise RkyvError {
  require_validation_depth(remaining_depth)
  match self {
    Schema::U8 => {
      let _ = reader.read_u8(offset)
    }
    Schema::U16 => {
      let _ = reader.read_u16(offset)
    }
    Schema::U32 => {
      let _ = reader.read_u32(offset)
    }
    Schema::U64 => {
      let _ = reader.read_u64(offset)
    }
    Schema::I8 => {
      let _ = reader.read_i8(offset)
    }
    Schema::I16 => {
      let _ = reader.read_i16(offset)
    }
    Schema::I32 => {
      let _ = reader.read_i32(offset)
    }
    Schema::I64 => {
      let _ = reader.read_i64(offset)
    }
    Schema::F32 => {
      let _ = reader.read_f32(offset)
    }
    Schema::F64 => {
      let _ = reader.read_f64(offset)
    }
    Schema::Bool => {
      let _ = reader.read_bool_strict(offset)
    }
    Schema::String => {
      let _ = reader.read_string(offset)
    }
    Schema::VecU32 => {
      let _ = reader.read_vec_u32(offset)
    }
    Schema::Vec(element_schema) => {
      let element_layout = element_schema.layout()
      let header = reader.read_vec_header_with_element_size(
        offset,
        element_layout.size,
      )
      for index in 0..<header.length {
        element_schema.validate_at(
          reader,
          header.data_offset + index * element_layout.size,
          remaining_depth - 1,
        )
      }
    }
    Schema::Option(value_schema) =>
      match
        reader.read_option_value_offset_strict(
          offset,
          value_schema.layout().alignment,
        ) {
        None => ()
        Some(value_offset) =>
          value_schema.validate_at(reader, value_offset, remaining_depth - 1)
      }
    Schema::Struct(fields) | Schema::StructLayout(fields, _, _) => {
      let layout = self.layout()
      for index in 0..<fields.length() {
        fields[index].schema.validate_at(
          reader,
          offset + layout.field_offsets[index],
          remaining_depth - 1,
        )
      }
    }
    Schema::TaggedUnion(variants, tag_offset, payload_offset, _) => {
      let tag = reader.read_u8(offset + tag_offset)
      let mut found : Variant? = None
      for variant in variants {
        if variant.tag == tag {
          found = Some(variant)
        }
      }
      match found {
        None => raise RkyvError::InvalidUnionTag(tag)
        Some(variant) =>
          variant.schema.validate_at(
            reader,
            offset + payload_offset,
            remaining_depth - 1,
          )
      }
    }
  }
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
    Schema::Struct(fields) | Schema::StructLayout(fields, _, _) => {
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
/// Opens the present value of a host-defined `Option<T>`. `None` means either
/// this view is not optional or the archived value is absent.
pub fn View::option_value(self : View) -> View? raise RkyvError {
  match self.schema {
    Schema::Option(value_schema) => {
      let value_layout = value_schema.layout()
      match
        self.reader.read_option_value_offset(
          self.offset,
          value_layout.alignment,
        ) {
        None => None
        Some(offset) =>
          Some({ schema: value_schema, reader: self.reader, offset })
      }
    }
    _ => None
  }
}

///|
/// Reads an explicit tagged-union discriminant without resolving its payload.
pub fn View::read_tag(self : View) -> Byte? raise RkyvError {
  match self.schema {
    Schema::TaggedUnion(_, tag_offset, _, _) =>
      Some(self.reader.read_u8(self.offset + tag_offset))
    _ => None
  }
}

///|
/// Opens the active explicit tagged-union payload. Unknown tags are rejected
/// rather than treated as absent, which keeps untrusted validation strict.
pub fn View::tagged_value(self : View) -> View? raise RkyvError {
  match self.schema {
    Schema::TaggedUnion(variants, tag_offset, payload_offset, _) => {
      let tag = self.reader.read_u8(self.offset + tag_offset)
      let mut found : Variant? = None
      for variant in variants {
        if variant.tag == tag {
          found = Some(variant)
        }
      }
      match found {
        None => raise RkyvError::InvalidUnionTag(tag)
        Some(variant) =>
          if variant.schema.layout().size == 0 {
            None
          } else {
            Some({
              schema: variant.schema,
              reader: self.reader,
              offset: self.offset + payload_offset,
            })
          }
      }
    }
    _ => None
  }
}

///|
/// Returns a nested mutable struct field by name. `None` means this view is
/// not a struct or that the requested field does not exist.
pub fn MutView::field(self : MutView, name : String) -> MutView? {
  match self.schema {
    Schema::Struct(fields) | Schema::StructLayout(fields, _, _) => {
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
/// Reads a `u8` when this view's schema is `Schema::U8`.
pub fn View::read_u8(self : View) -> Byte? raise RkyvError {
  match self.schema {
    Schema::U8 => Some(self.reader.read_u8(self.offset))
    _ => None
  }
}

///|
/// Reads a `u16` when this view's schema is `Schema::U16`.
pub fn View::read_u16(self : View) -> UInt? raise RkyvError {
  match self.schema {
    Schema::U16 => Some(self.reader.read_u16(self.offset))
    _ => None
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
/// Reads a `u64` when this view's schema is `Schema::U64`.
pub fn View::read_u64(self : View) -> UInt64? raise RkyvError {
  match self.schema {
    Schema::U64 => Some(self.reader.read_u64(self.offset))
    _ => None
  }
}

///|
/// Reads an `i8` when this view's schema is `Schema::I8`.
pub fn View::read_i8(self : View) -> Int? raise RkyvError {
  match self.schema {
    Schema::I8 => Some(self.reader.read_i8(self.offset))
    _ => None
  }
}

///|
/// Reads an `i16` when this view's schema is `Schema::I16`.
pub fn View::read_i16(self : View) -> Int? raise RkyvError {
  match self.schema {
    Schema::I16 => Some(self.reader.read_i16(self.offset))
    _ => None
  }
}

///|
/// Reads an `i32` when this view's schema is `Schema::I32`.
pub fn View::read_i32(self : View) -> Int? raise RkyvError {
  match self.schema {
    Schema::I32 => Some(self.reader.read_i32(self.offset))
    _ => None
  }
}

///|
/// Reads an `i64` when this view's schema is `Schema::I64`.
pub fn View::read_i64(self : View) -> Int64? raise RkyvError {
  match self.schema {
    Schema::I64 => Some(self.reader.read_i64(self.offset))
    _ => None
  }
}

///|
/// Reads an `f32` when this view's schema is `Schema::F32`.
pub fn View::read_f32(self : View) -> Float? raise RkyvError {
  match self.schema {
    Schema::F32 => Some(self.reader.read_f32(self.offset))
    _ => None
  }
}

///|
/// Reads an `f64` when this view's schema is `Schema::F64`.
pub fn View::read_f64(self : View) -> Double? raise RkyvError {
  match self.schema {
    Schema::F64 => Some(self.reader.read_f64(self.offset))
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
    Schema::VecU32 | Schema::Vec(Schema::U32) =>
      Some(self.reader.read_vec_u32(self.offset))
    _ => None
  }
}

///|
/// Materializes a generic `ArchivedVec<i16>` after validating its complete
/// span. The dedicated lazy `U32VecView` remains available for the hot u32
/// path; other primitive vectors favor a compact general implementation.
pub fn View::read_vec_i16(self : View) -> Array[Int]? raise RkyvError {
  match self.schema {
    Schema::Vec(Schema::I16) => {
      let header = self.reader.read_vec_header_with_element_size(self.offset, 2)
      let values : Array[Int] = []
      for index in 0..<header.length {
        values.push(self.reader.read_i16(header.data_offset + index * 2))
      }
      Some(values)
    }
    _ => None
  }
}

///|
/// Materializes a generic `ArchivedVec<u64>` after validating its complete
/// span. It is useful for host-side inspection and test conformance; generated
/// bindings use lazy per-field views for all primitive vectors.
pub fn View::read_vec_u64(self : View) -> Array[UInt64]? raise RkyvError {
  match self.schema {
    Schema::Vec(Schema::U64) => {
      let header = self.reader.read_vec_header_with_element_size(self.offset, 8)
      let values : Array[UInt64] = []
      for index in 0..<header.length {
        values.push(self.reader.read_u64(header.data_offset + index * 8))
      }
      Some(values)
    }
    _ => None
  }
}
