///|
pub struct AccountView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn AccountView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> Result[AccountView, @rkyv.RkyvError] {
  match reader.validate_range(offset, 12) {
    Ok(_) => Ok({ reader, offset })
    Err(error) => Err(error)
  }
}

///|
pub fn AccountView::root(bytes : Bytes) -> Result[AccountView, @rkyv.RkyvError] {
  let reader = @rkyv.Reader::new(bytes)
  match reader.root_offset(12) {
    Ok(offset) => AccountView::at(reader, offset)
    Err(error) => Err(error)
  }
}

///|
pub fn AccountView::id(self : AccountView) -> Result[UInt, @rkyv.RkyvError] {
  self.reader.read_u32(self.offset)
}

///|
pub fn AccountView::profile(
  self : AccountView,
) -> Result[ProfileView, @rkyv.RkyvError] {
  ProfileView::at(self.reader, self.offset + 4)
}
