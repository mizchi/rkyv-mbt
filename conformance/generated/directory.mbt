///|
pub struct DirectoryView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn DirectoryView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> DirectoryView raise @rkyv.RkyvError {
  reader.validate_range(offset, 8)
  { reader, offset }
}

///|
pub fn DirectoryView::root(
  bytes : Bytes,
) -> DirectoryView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(8)
  DirectoryView::at(reader, offset)
}

///|
pub fn DirectoryView::entries(
  self : DirectoryView,
) -> DirectoryEntriesView raise @rkyv.RkyvError {
  let header = self.reader.read_vec_header_with_element_size(self.offset, 8)
  {
    reader: self.reader,
    data_offset: header.data_offset,
    length: header.length,
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
) -> ProfileView? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(ProfileView::at(self.reader, self.data_offset + index * 8))
  }
}
