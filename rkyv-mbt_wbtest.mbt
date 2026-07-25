// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
/// The default rkyv profile has a fixed 8-byte `ArchivedVec` header. Its
/// specialized helper must retain the generic reader's bounds guarantees.
test "default Vec<u32> header helper validates the complete element span" {
  let valid = Reader::new(
    Bytes::from_array([
      b'\x01', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x03',
      b'\x00', b'\x00', b'\x00', b'\xf4', b'\xff', b'\xff', b'\xff', b'\x03', b'\x00',
      b'\x00', b'\x00',
    ]),
  )
  match valid.read_default_vec_u32_header(12) {
    Err(_) => fail("valid default Vec<u32> header was rejected")
    Ok(header) => {
      assert_eq(header.data_offset, 0)
      assert_eq(header.length, 3)
    }
  }

  let truncated = Reader::new(
    Bytes::from_array([
      b'\x08', b'\x00', b'\x00', b'\x00', b'\x03', b'\x00', b'\x00', b'\x00', b'\x01',
      b'\x00', b'\x00', b'\x00',
    ]),
  )
  match truncated.read_default_vec_u32_header(0) {
    Ok(_) => fail("truncated default Vec<u32> header was accepted")
    Err(RkyvError::InvalidCollectionLength(length)) => assert_eq(length, 3)
    Err(_) => fail("truncated default Vec<u32> returned the wrong error")
  }
}
