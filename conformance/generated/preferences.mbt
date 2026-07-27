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
pub fn PreferencesView::validate(
  bytes : Bytes,
) -> PreferencesView raise @rkyv.RkyvError {
  let view = PreferencesView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn PreferencesView::validate_all(
  self : PreferencesView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  match self.reader.read_option_value_offset_strict(self.offset, 4) {
    None => ()
    Some(value_offset) => {
      let _ = self.reader.read_u32(value_offset)
    }
  }
  match self.reader.read_option_value_offset_strict(self.offset + 8, 4) {
    None => ()
    Some(value_offset) => {
      let _ = self.reader.read_string(value_offset)
    }
  }
  match self.reader.read_option_value_offset_strict(self.offset + 20, 4) {
    None => ()
    Some(value_offset) => {
      let value = ProfileView::at(self.reader, value_offset)
      value.validate_all(remaining_depth - 1)
    }
  }
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
