///|
pub struct UserView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn UserView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> Result[UserView, @rkyv.RkyvError] {
  match reader.validate_range(offset, 24) {
    Ok(_) => Ok({ reader, offset })
    Err(error) => Err(error)
  }
}

///|
pub fn UserView::root(bytes : Bytes) -> Result[UserView, @rkyv.RkyvError] {
  let reader = @rkyv.Reader::new(bytes)
  match reader.root_offset(24) {
    Ok(offset) => UserView::at(reader, offset)
    Err(error) => Err(error)
  }
}

///|
pub fn UserView::id(self : UserView) -> Result[UInt, @rkyv.RkyvError] {
  self.reader.read_u32(self.offset)
}

///|
pub fn UserView::active(self : UserView) -> Result[Bool, @rkyv.RkyvError] {
  self.reader.read_bool(self.offset + 4)
}

///|
pub fn UserView::name(self : UserView) -> Result[String, @rkyv.RkyvError] {
  self.reader.read_string(self.offset + 8)
}

///|
pub fn UserView::scores(
  self : UserView,
) -> Result[@rkyv.U32VecView, @rkyv.RkyvError] {
  self.reader.read_vec_u32(self.offset + 16)
}
