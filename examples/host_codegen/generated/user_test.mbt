///|
/// The generated API has no field-name lookups or type-dispatched setters at
/// the call site. It exposes only the operations valid for the User schema.
test "typed User views patch an archive in place" {
  let archive = encode(42U, true, "Ada", [7U, 11U, 13U])
  let writer = UserMutView::root(archive.mut_view())
  writer.set_id(99U)
  writer.set_active(false)
  assert_eq(writer.set_name_same_length("Eve"), true)
  let scores = writer.scores_mut()
  assert_eq(scores.set(1, 42U), true)

  let reader = UserView::root(Bytes::from_array(archive))
  assert_eq(reader.id(), 99U)
  assert_eq(reader.active(), false)
  assert_eq(reader.name(), "Eve")
  assert_eq(reader.scores().to_array(), [7U, 42U, 13U])
}
