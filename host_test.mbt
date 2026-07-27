///|
/// A host-defined schema must emit the same default-format archive as the
/// matching Rust `Archived<User>` fixture without involving a Rust generator.
test "encodes a host-defined User schema in the rkyv default format" {
  let user = Schema::Struct([
    { name: "id", schema: Schema::U32 },
    { name: "active", schema: Schema::Bool },
    { name: "name", schema: Schema::String },
    { name: "scores", schema: Schema::VecU32 },
  ])
  let archive = user.encode(
    Value::Struct([
      { name: "id", value: Value::U32(42U) },
      { name: "active", value: Value::Bool(true) },
      { name: "name", value: Value::String("Ada") },
      { name: "scores", value: Value::VecU32([7U, 11U, 13U]) },
    ]),
  )
  assert_eq(
    archive,
    Bytes::from_array([
      b'\x07', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x0d',
      b'\x00', b'\x00', b'\x00', b'\x2a', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00',
      b'\x00', b'\x00', b'A', b'd', b'a', b'\xff', b'\xff', b'\xff', b'\xff', b'\xff',
      b'\xe4', b'\xff', b'\xff', b'\xff', b'\x03', b'\x00', b'\x00', b'\x00',
    ]),
  )
  let root = user.root(archive)
  match root.field("id") {
    None => fail("host view did not find id")
    Some(id) => assert_eq(id.read_u32(), Some(42U))
  }
  match root.field("active") {
    None => fail("host view did not find active")
    Some(active) => assert_eq(active.read_bool(), Some(true))
  }
  match root.field("name") {
    None => fail("host view did not find name")
    Some(name) => assert_eq(name.read_string(), Some("Ada"))
  }
  match root.field("scores") {
    None => fail("host view did not find scores")
    Some(scores) =>
      match scores.read_vec_u32() {
        None => fail("host view did not expose Vec<u32>")
        Some(values) => assert_eq(values.to_array(), [7U, 11U, 13U])
      }
  }
}

///|
/// Nested host schemas preserve inline struct layout while placing their
/// out-of-line dependencies before the root archive object.
test "encodes nested host-defined structs" {
  let profile = Schema::Struct([
    { name: "age", schema: Schema::U32 },
    { name: "subscribed", schema: Schema::Bool },
  ])
  let account = Schema::Struct([
    { name: "id", schema: Schema::U32 },
    { name: "profile", schema: profile },
  ])
  let archive = account.encode(
    Value::Struct([
      { name: "id", value: Value::U32(99U) },
      {
        name: "profile",
        value: Value::Struct([
          { name: "age", value: Value::U32(33U) },
          { name: "subscribed", value: Value::Bool(true) },
        ]),
      },
    ]),
  )
  assert_eq(
    archive,
    Bytes::from_array([
      b'\x63', b'\x00', b'\x00', b'\x00', b'\x21', b'\x00', b'\x00', b'\x00', b'\x01',
      b'\x00', b'\x00', b'\x00',
    ]),
  )
}

///|
/// A Rust-derived layout may contain padding that cannot be reconstructed from
/// declaration order alone. Explicit field offsets must control both writes
/// and subsequent zero-copy field lookup.
test "encodes an explicit Rust struct layout with padding" {
  let schema = Schema::StructLayout(
    [
      { name: "active", schema: Schema::Bool },
      { name: "id", schema: Schema::U32 },
    ],
    [0, 8],
    12,
  )
  let archive = schema.encode(
    Value::Struct([
      { name: "active", value: Value::Bool(true) },
      { name: "id", value: Value::U32(0x12345678U) },
    ]),
  )
  assert_eq(
    archive,
    Bytes::from_array([
      b'\x01', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x78',
      b'\x56', b'\x34', b'\x12',
    ]),
  )
  let root = schema.root(archive)
  match root.field("id") {
    None => fail("explicit layout did not expose id")
    Some(id) => assert_eq(id.read_u32(), Some(0x12345678U))
  }
}

///|
/// Generic vectors and options let generated Rust struct bindings encode the
/// same recursive shapes that their lazy readers expose.
test "encodes generic vectors and optional host values" {
  let schema = Schema::Struct([
    { name: "labels", schema: Schema::Vec(Schema::String) },
    { name: "stock", schema: Schema::Option(Schema::U32) },
  ])
  let archive = schema.encode(
    Value::Struct([
      {
        name: "labels",
        value: Value::Vec([Value::String("kitchen"), Value::String("gift")]),
      },
      { name: "stock", value: Value::Option(Some(Value::U32(12U))) },
    ]),
  )
  let root = schema.root(archive)
  match root.field("stock") {
    None => fail("host view did not find optional stock")
    Some(stock) =>
      match stock.option_value() {
        None => fail("host view did not expose Some stock")
        Some(value) => assert_eq(value.read_u32(), Some(12U))
      }
  }
}

///|
/// Every fixed-width primitive uses its rkyv archive representation, so the
/// host encoder can produce a Rust-readable record without a Rust writer.
test "encodes every fixed-width primitive through the host schema" {
  let schema = Schema::Struct([
    { name: "u8", schema: Schema::U8 },
    { name: "u16", schema: Schema::U16 },
    { name: "u32", schema: Schema::U32 },
    { name: "u64", schema: Schema::U64 },
    { name: "i8", schema: Schema::I8 },
    { name: "i16", schema: Schema::I16 },
    { name: "i32", schema: Schema::I32 },
    { name: "i64", schema: Schema::I64 },
    { name: "f32", schema: Schema::F32 },
    { name: "f64", schema: Schema::F64 },
  ])
  let archive = schema.encode(
    Value::Struct([
      { name: "u8", value: Value::U8(b'\xab') },
      { name: "u16", value: Value::U16(0xcdefU) },
      { name: "u32", value: Value::U32(0x01234567U) },
      { name: "u64", value: Value::U64(0x0123456789abcdefUL) },
      { name: "i8", value: Value::I8(-7) },
      { name: "i16", value: Value::I16(-1000) },
      { name: "i32", value: Value::I32(-123456789) },
      { name: "i64", value: Value::I64(-1234567890123456789L) },
      { name: "f32", value: Value::F32(1.5) },
      { name: "f64", value: Value::F64(-2.25) },
    ]),
  )
  let root = schema.root(archive)
  match root.field("u8") {
    Some(value) => assert_eq(value.read_u8(), Some(b'\xab'))
    None => fail("u8 field missing")
  }
  match root.field("u16") {
    Some(value) => assert_eq(value.read_u16(), Some(0xcdefU))
    None => fail("u16 field missing")
  }
  match root.field("u32") {
    Some(value) => assert_eq(value.read_u32(), Some(0x01234567U))
    None => fail("u32 field missing")
  }
  match root.field("u64") {
    Some(value) => assert_eq(value.read_u64(), Some(0x0123456789abcdefUL))
    None => fail("u64 field missing")
  }
  match root.field("i8") {
    Some(value) => assert_eq(value.read_i8(), Some(-7))
    None => fail("i8 field missing")
  }
  match root.field("i16") {
    Some(value) => assert_eq(value.read_i16(), Some(-1000))
    None => fail("i16 field missing")
  }
  match root.field("i32") {
    Some(value) => assert_eq(value.read_i32(), Some(-123456789))
    None => fail("i32 field missing")
  }
  match root.field("i64") {
    Some(value) => assert_eq(value.read_i64(), Some(-1234567890123456789L))
    None => fail("i64 field missing")
  }
  match root.field("f32") {
    Some(value) => assert_true(value.read_f32() == Some(1.5))
    None => fail("f32 field missing")
  }
  match root.field("f64") {
    Some(value) => assert_true(value.read_f64() == Some(-2.25))
    None => fail("f64 field missing")
  }
}

///|
/// The generic vector writer must retain the nested element schema when it is
/// wrapped in `Option`, including fixed-width elements that do not need a
/// dedicated runtime view.
test "encodes optional vectors of primitive values" {
  let schema = Schema::Struct([
    { name: "signed", schema: Schema::Option(Schema::Vec(Schema::I16)) },
    { name: "numbers", schema: Schema::Vec(Schema::U64) },
  ])
  let archive = schema.encode(
    Value::Struct([
      {
        name: "signed",
        value: Value::Option(Some(Value::Vec([Value::I16(-1), Value::I16(7)]))),
      },
      {
        name: "numbers",
        value: Value::Vec([Value::U64(1UL), Value::U64(0x0123456789abcdefUL)]),
      },
    ]),
  )
  let root = schema.root(archive)
  match root.field("signed") {
    Some(value) =>
      match value.option_value() {
        Some(vector) => assert_eq(vector.read_vec_i16(), Some([-1, 7]))
        None => fail("optional vector was missing")
      }
    None => fail("signed field missing")
  }
  match root.field("numbers") {
    Some(value) =>
      assert_eq(value.read_vec_u64(), Some([1UL, 0x0123456789abcdefUL]))
    None => fail("numbers field missing")
  }
}

///|
/// Tagged unions model rkyv's `#[repr(u8)]` archived enum layout explicitly:
/// a one-byte discriminant and an explicit, compiler-provided payload offset.
test "encodes and validates an explicit tagged union" {
  let union = Schema::TaggedUnion(
    [
      { name: "Empty", tag: b'\x00', schema: Schema::Struct([]) },
      { name: "Count", tag: b'\x01', schema: Schema::U32 },
      { name: "Label", tag: b'\x02', schema: Schema::String },
    ],
    0,
    4,
    12,
  )
  let archive = union.encode(
    Value::Tagged(b'\x02', Some(Value::String("mint"))),
  )
  assert_eq(
    archive,
    Bytes::from_array([
      b'\x02', b'\x00', b'\x00', b'\x00', b'm', b'i', b'n', b't', b'\xff', b'\xff',
      b'\xff', b'\xff',
    ]),
  )
  let root = union.root(archive)
  assert_eq(root.read_tag(), Some(b'\x02'))
  match root.tagged_value() {
    Some(value) => assert_eq(value.read_string(), Some("mint"))
    None => fail("tagged payload missing")
  }
  union.validate(archive)
}

///|
/// Schema values are named so an accidental schema/value order mismatch cannot
/// silently write a valid archive for the wrong field.
test "rejects a host value whose field does not match its schema" {
  let schema = Schema::Struct([{ name: "id", schema: Schema::U32 }])
  let mut raised = false
  try {
    let _ = schema.encode(
      Value::Struct([{ name: "name", value: Value::U32(1U) }]),
    )
    fail("a mismatched host field was accepted")
  } catch {
    SchemaError::FieldMismatch(expected~, actual~) => {
      assert_eq(expected, "id")
      assert_eq(actual, "name")
      raised = true
    }
    _ => fail("mismatched host field raised the wrong error")
  }
  assert_true(raised)
}

///|
/// The pure MoonBit host encoder and view handle rkyv's out-of-line string
/// representation, which is the same path emitted by a JavaScript build.
test "encodes and reads a host-defined out-of-line String" {
  let schema = Schema::String
  let archive = schema.encode(Value::String("hello rkyv"))
  assert_eq(archive, encode_string("hello rkyv"))
  assert_eq(schema.root(archive).read_string(), Some("hello rkyv"))
}

///|
/// An out-of-line dependency inside a struct is relative to the field's final
/// root offset, not merely to the start of the dependency area.
test "encodes out-of-line host fields relative to their struct offsets" {
  let schema = Schema::Struct([
    { name: "title", schema: Schema::String },
    { name: "scores", schema: Schema::VecU32 },
  ])
  let archive = schema.encode(
    Value::Struct([
      { name: "title", value: Value::String("hello rkyv") },
      { name: "scores", value: Value::VecU32([7U, 11U]) },
    ]),
  )
  assert_eq(
    archive,
    Bytes::from_array([
      b'h', b'e', b'l', b'l', b'o', b' ', b'r', b'k', b'y', b'v', b'\x00', b'\x00',
      b'\x07', b'\x00', b'\x00', b'\x00', b'\x0b', b'\x00', b'\x00', b'\x00', b'\x8a',
      b'\x00', b'\x00', b'\x00', b'\xec', b'\xff', b'\xff', b'\xff', b'\xf0', b'\xff',
      b'\xff', b'\xff', b'\x02', b'\x00', b'\x00', b'\x00',
    ]),
  )
  let root = schema.root(archive)
  match root.field("title") {
    None => fail("host view did not find title")
    Some(title) => assert_eq(title.read_string(), Some("hello rkyv"))
  }
  match root.field("scores") {
    None => fail("host view did not find scores")
    Some(scores) =>
      match scores.read_vec_u32() {
        None => fail("host view did not expose scores")
        Some(scores) => assert_eq(scores.to_array(), [7U, 11U])
      }
  }
}

///|
/// Fixed-width fields and existing vector elements can be updated in the
/// caller-owned archive buffer without allocating another archive.
test "mutates host schema fields in place" {
  let schema = Schema::Struct([
    { name: "id", schema: Schema::U32 },
    { name: "active", schema: Schema::Bool },
    { name: "name", schema: Schema::String },
    { name: "scores", schema: Schema::VecU32 },
  ])
  let archive = schema.encode_mut(
    Value::Struct([
      { name: "id", value: Value::U32(42U) },
      { name: "active", value: Value::Bool(true) },
      { name: "name", value: Value::String("Ada") },
      { name: "scores", value: Value::VecU32([7U, 11U, 13U]) },
    ]),
  )
  let root = schema.root_mut(archive.mut_view())
  match root.field("id") {
    None => fail("mutable view did not find id")
    Some(id) => assert_eq(id.set_u32(99U), true)
  }
  match root.field("active") {
    None => fail("mutable view did not find active")
    Some(active) => assert_eq(active.set_bool(false), true)
  }
  match root.field("name") {
    None => fail("mutable view did not find name")
    Some(name) => {
      assert_eq(name.set_string("Eve"), true)
      assert_eq(name.set_string("longer"), false)
    }
  }
  match root.field("scores") {
    None => fail("mutable view did not find scores")
    Some(scores) =>
      match scores.vec_u32_mut() {
        None => fail("mutable view did not expose scores")
        Some(scores) => {
          assert_eq(scores.length(), 3)
          assert_eq(scores.set(1, 42U), true)
          assert_eq(scores.set(3, 99U), false)
        }
      }
  }
  let updated = schema.root(Bytes::from_array(archive))
  match updated.field("id") {
    None => fail("updated view did not find id")
    Some(id) => assert_eq(id.read_u32(), Some(99U))
  }
  match updated.field("active") {
    None => fail("updated view did not find active")
    Some(active) => assert_eq(active.read_bool(), Some(false))
  }
  match updated.field("name") {
    None => fail("updated view did not find name")
    Some(name) => assert_eq(name.read_string(), Some("Eve"))
  }
  match updated.field("scores") {
    None => fail("updated view did not find scores")
    Some(scores) =>
      match scores.read_vec_u32() {
        None => fail("updated view did not expose scores")
        Some(scores) => assert_eq(scores.to_array(), [7U, 42U, 13U])
      }
  }
}

///|
/// Long strings use an out-of-line relative pointer, which remains valid when
/// the replacement preserves the exact UTF-8 byte length.
test "mutates an out-of-line string without relocating it" {
  let schema = Schema::String
  let archive = schema.encode_mut(Value::String("hello rkyv"))
  let root = schema.root_mut(archive.mut_view())
  assert_eq(root.set_string("world rkyv"), true)
  assert_eq(root.set_string("short"), false)
  assert_eq(
    schema.root(Bytes::from_array(archive)).read_string(),
    Some("world rkyv"),
  )
}
