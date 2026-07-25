///|
pub struct DirectoryView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn DirectoryView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> Result[DirectoryView, @rkyv.RkyvError] {
  match reader.validate_range(offset, 8) {
    Ok(_) => Ok({ reader, offset })
    Err(error) => Err(error)
  }
}

///|
pub fn DirectoryView::root(
  bytes : Bytes,
) -> Result[DirectoryView, @rkyv.RkyvError] {
  let reader = @rkyv.Reader::new(bytes)
  match reader.root_offset(8) {
    Ok(offset) => DirectoryView::at(reader, offset)
    Err(error) => Err(error)
  }
}

///|
pub fn DirectoryView::entries(
  self : DirectoryView,
) -> Result[DirectoryEntriesView, @rkyv.RkyvError] {
  match self.reader.read_vec_header_with_element_size(self.offset, 8) {
    Err(error) => Err(error)
    Ok(header) =>
      Ok({
        reader: self.reader,
        data_offset: header.data_offset,
        length: header.length,
      })
  }
}

///|
pub struct DirectoryEntriesView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn DirectoryEntriesView::length(self : DirectoryEntriesView) -> Int {
  self.length
}

///|
pub fn DirectoryEntriesView::at(
  self : DirectoryEntriesView,
  index : Int,
) -> Result[ProfileView?, @rkyv.RkyvError] {
  if index < 0 || index >= self.length {
    Ok(None)
  } else {
    match ProfileView::at(self.reader, self.data_offset + index * 8) {
      Err(error) => Err(error)
      Ok(value) => Ok(Some(value))
    }
  }
}
