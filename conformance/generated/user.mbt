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
