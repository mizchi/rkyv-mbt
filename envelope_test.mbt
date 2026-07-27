///|
/// Envelopes make the runtime format self-identifying and reject corruption
/// before an untrusted rkyv schema starts following relative pointers.
test "round trips a versioned archive envelope" {
  let payload = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let encoded = encode_envelope(payload)
  let decoded = decode_envelope(encoded)
  assert_eq(decoded.payload, payload)
  assert_eq(decoded.version, 1)
  assert_eq(decoded.format, default_format())
}

///|
/// Checksum and format errors are distinct from rkyv layout validation errors.
test "rejects a corrupted archive envelope before reading its payload" {
  let bytes = encode_envelope(Bytes::from_array([b'\x01', b'\x02']))
  let changed = bytes.to_array()
  changed[16] = b'\xff'
  let mut raised = false
  try {
    let _ = decode_envelope(Bytes::from_array(changed))
    fail("corrupted envelope was accepted")
  } catch {
    EnvelopeError::ChecksumMismatch(..) => raised = true
    _ => fail("corrupted envelope raised the wrong error")
  }
  assert_true(raised)
}

///|
/// Callers can put a hard allocation ceiling in front of untrusted payloads.
test "rejects an envelope that exceeds the caller payload limit" {
  let bytes = encode_envelope(Bytes::from_array([b'\x01', b'\x02', b'\x03']))
  let mut raised = false
  try {
    let _ = decode_envelope_with_limit(bytes, 2)
    fail("oversized envelope was accepted")
  } catch {
    EnvelopeError::PayloadLimitExceeded(..) => raised = true
    _ => fail("oversized envelope raised the wrong error")
  }
  assert_true(raised)
}
