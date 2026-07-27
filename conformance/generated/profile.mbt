///|
pub struct ProfileView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn ProfileView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> ProfileView raise @rkyv.RkyvError {
  reader.validate_range(offset, 8)
  { reader, offset }
}

///|
pub fn ProfileView::root(bytes : Bytes) -> ProfileView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(8)
  ProfileView::at(reader, offset)
}

///|
pub fn ProfileView::validate(
  bytes : Bytes,
) -> ProfileView raise @rkyv.RkyvError {
  let view = ProfileView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn ProfileView::validate_all(
  self : ProfileView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let _ = self.reader.read_u32(self.offset)
  let _ = self.reader.read_bool_strict(self.offset + 4)
}

///|
pub fn ProfileView::age(self : ProfileView) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset)
}

///|
pub fn ProfileView::subscribed(
  self : ProfileView,
) -> Bool raise @rkyv.RkyvError {
  self.reader.read_bool(self.offset + 4)
}
