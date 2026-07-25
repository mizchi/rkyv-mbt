///|
pub struct ProfileView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn ProfileView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> Result[ProfileView, @rkyv.RkyvError] {
  match reader.validate_range(offset, 8) {
    Ok(_) => Ok({ reader, offset })
    Err(error) => Err(error)
  }
}

///|
pub fn ProfileView::root(bytes : Bytes) -> Result[ProfileView, @rkyv.RkyvError] {
  let reader = @rkyv.Reader::new(bytes)
  match reader.root_offset(8) {
    Ok(offset) => ProfileView::at(reader, offset)
    Err(error) => Err(error)
  }
}

///|
pub fn ProfileView::age(self : ProfileView) -> Result[UInt, @rkyv.RkyvError] {
  self.reader.read_u32(self.offset)
}

///|
pub fn ProfileView::subscribed(
  self : ProfileView,
) -> Result[Bool, @rkyv.RkyvError] {
  self.reader.read_bool(self.offset + 4)
}
