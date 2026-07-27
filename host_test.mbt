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
