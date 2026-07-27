///|
pub struct AccountView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn AccountView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> AccountView raise @rkyv.RkyvError {
  reader.validate_range(offset, 12)
  { reader, offset }
}

///|
pub fn AccountView::root(bytes : Bytes) -> AccountView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(12)
  AccountView::at(reader, offset)
}

///|
pub fn AccountView::validate(
  bytes : Bytes,
) -> AccountView raise @rkyv.RkyvError {
  let view = AccountView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn AccountView::validate_all(
  self : AccountView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let _ = self.reader.read_u32(self.offset)
  let value = ProfileView::at(self.reader, self.offset + 4)
  value.validate_all(remaining_depth - 1)
}

///|
pub fn AccountView::id(self : AccountView) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset)
}

///|
pub fn AccountView::profile(
  self : AccountView,
) -> ProfileView raise @rkyv.RkyvError {
  ProfileView::at(self.reader, self.offset + 4)
}
