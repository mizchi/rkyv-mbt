///|
pub struct PreferencesView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn PreferencesView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> Result[PreferencesView, @rkyv.RkyvError] {
  match reader.validate_range(offset, 32) {
    Ok(_) => Ok({ reader, offset })
    Err(error) => Err(error)
  }
}

///|
pub fn PreferencesView::root(
  bytes : Bytes,
) -> Result[PreferencesView, @rkyv.RkyvError] {
  let reader = @rkyv.Reader::new(bytes)
  match reader.root_offset(32) {
    Ok(offset) => PreferencesView::at(reader, offset)
    Err(error) => Err(error)
  }
}

///|
pub fn PreferencesView::retries(
  self : PreferencesView,
) -> Result[UInt?, @rkyv.RkyvError] {
  match self.reader.read_option_value_offset(self.offset, 4) {
    Err(error) => Err(error)
    Ok(None) => Ok(None)
    Ok(Some(value_offset)) =>
      match self.reader.read_u32(value_offset) {
        Err(error) => Err(error)
        Ok(value) => Ok(Some(value))
      }
  }
}

///|
pub fn PreferencesView::nickname(
  self : PreferencesView,
) -> Result[String?, @rkyv.RkyvError] {
  match self.reader.read_option_value_offset(self.offset + 8, 4) {
    Err(error) => Err(error)
    Ok(None) => Ok(None)
    Ok(Some(value_offset)) =>
      match self.reader.read_string(value_offset) {
        Err(error) => Err(error)
        Ok(value) => Ok(Some(value))
      }
  }
}

///|
pub fn PreferencesView::profile(
  self : PreferencesView,
) -> Result[ProfileView?, @rkyv.RkyvError] {
  match self.reader.read_option_value_offset(self.offset + 20, 4) {
    Err(error) => Err(error)
    Ok(None) => Ok(None)
    Ok(Some(value_offset)) =>
      match ProfileView::at(self.reader, value_offset) {
        Err(error) => Err(error)
        Ok(value) => Ok(Some(value))
      }
  }
}
