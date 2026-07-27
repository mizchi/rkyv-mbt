///|
pub struct UserView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn UserView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> UserView raise @rkyv.RkyvError {
  reader.validate_range(offset, 24)
  { reader, offset }
}

///|
pub fn UserView::root(bytes : Bytes) -> UserView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(24)
  UserView::at(reader, offset)
}

///|
pub fn UserView::validate(bytes : Bytes) -> UserView raise @rkyv.RkyvError {
  let view = UserView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn UserView::validate_all(
  self : UserView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let _ = self.reader.read_u32(self.offset)
  let _ = self.reader.read_bool_strict(self.offset + 4)
  let _ = self.reader.read_string(self.offset + 8)
  let _ = self.reader.read_vec_u32(self.offset + 16)
}

///|
pub fn UserView::id(self : UserView) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset)
}

///|
pub fn UserView::active(self : UserView) -> Bool raise @rkyv.RkyvError {
  self.reader.read_bool(self.offset + 4)
}

///|
pub fn UserView::name(self : UserView) -> String raise @rkyv.RkyvError {
  self.reader.read_string(self.offset + 8)
}

///|
pub fn UserView::scores(
  self : UserView,
) -> @rkyv.U32VecView raise @rkyv.RkyvError {
  self.reader.read_vec_u32(self.offset + 16)
}
