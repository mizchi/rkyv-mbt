///|
pub struct PreferencesView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn PreferencesView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> PreferencesView raise @rkyv.RkyvError {
  reader.validate_range(offset, 32)
  { reader, offset }
}

///|
pub fn PreferencesView::root(
  bytes : Bytes,
) -> PreferencesView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(32)
  PreferencesView::at(reader, offset)
}

///|
pub fn PreferencesView::retries(
  self : PreferencesView,
) -> UInt? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset, 4) {
    None => None
    Some(value_offset) => Some(self.reader.read_u32(value_offset))
  }
}

///|
pub fn PreferencesView::nickname(
  self : PreferencesView,
) -> String? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset + 8, 4) {
    None => None
    Some(value_offset) => Some(self.reader.read_string(value_offset))
  }
}

///|
pub fn PreferencesView::profile(
  self : PreferencesView,
) -> ProfileView? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset + 20, 4) {
    None => None
    Some(value_offset) => Some(ProfileView::at(self.reader, value_offset))
  }
}
