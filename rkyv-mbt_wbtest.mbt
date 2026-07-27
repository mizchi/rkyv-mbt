// Whitebox tests run within the package scope.

///|
/// The specialized default-profile reader has the same validation contract as
/// the generic public reader while avoiding generic header dispatch.
test "default Vec<u32> view reader validates the complete element span" {
  let valid = Reader::new(
    Bytes::from_array([
      b'\x01', b'\x00', b'\x00', b'\x00', b'\x02', b'\x00', b'\x00', b'\x00', b'\x03',
      b'\x00', b'\x00', b'\x00', b'\xf4', b'\xff', b'\xff', b'\xff', b'\x03', b'\x00',
      b'\x00', b'\x00',
    ]),
  )
  let view = valid.read_default_vec_u32(12)
  assert_eq(view.data_byte_offset(), 0)
  assert_eq(view.length(), 3)

  let truncated = Reader::new(
    Bytes::from_array([
      b'\x08', b'\x00', b'\x00', b'\x00', b'\x03', b'\x00', b'\x00', b'\x00', b'\x01',
      b'\x00', b'\x00', b'\x00',
    ]),
  )
  let mut raised = false
  try {
    let _ = truncated.read_default_vec_u32(0)
    fail("truncated default Vec<u32> header was accepted")
  } catch {
    RkyvError::InvalidCollectionLength(length) => {
      assert_eq(length, 3)
      raised = true
    }
    _ => fail("truncated default Vec<u32> returned the wrong error")
  }
  assert_true(raised)
}
