///|
pub struct CatalogView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn CatalogView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> CatalogView raise @rkyv.RkyvError {
  reader.validate_range(offset, 12)
  { reader, offset }
}

///|
pub fn CatalogView::root(bytes : Bytes) -> CatalogView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(12)
  CatalogView::at(reader, offset)
}

///|
pub fn CatalogView::validate(
  bytes : Bytes,
) -> CatalogView raise @rkyv.RkyvError {
  let view = CatalogView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn CatalogView::validate_all(
  self : CatalogView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let _ = self.reader.read_u32(self.offset)
  let values = self.products()
  for index in 0..<values.length() {
    match values.at(index) {
      None => ()
      Some(value) => value.validate_all(remaining_depth - 1)
    }
  }
}

///|
pub fn CatalogView::revision(self : CatalogView) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset)
}

///|
pub fn CatalogView::products(
  self : CatalogView,
) -> CatalogProductsView raise @rkyv.RkyvError {
  let header = self.reader.read_vec_header_with_element_size(
    self.offset + 4,
    32,
  )
  {
    reader: self.reader,
    data_offset: header.data_offset,
    length: header.length,
  }
}

///|
pub struct CatalogProductsView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn CatalogProductsView::length(self : CatalogProductsView) -> Int {
  self.length
}

///|
pub fn CatalogProductsView::at(
  self : CatalogProductsView,
  index : Int,
) -> ProductView? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(ProductView::at(self.reader, self.data_offset + index * 32))
  }
}

///|
pub struct CatalogInput {
  revision : UInt
  products : Array[ProductInput]
}

///|
pub fn CatalogInput::new(
  revision : UInt,
  products : Array[ProductInput],
) -> CatalogInput {
  { revision, products }
}

///|
pub fn CatalogInput::schema() -> @rkyv.Schema {
  @rkyv.Schema::StructLayout(
    [
      { name: "revision", schema: @rkyv.Schema::U32 },
      { name: "products", schema: @rkyv.Schema::Vec(ProductInput::schema()) },
    ],
    [0, 4],
    12,
  )
}

///|
pub fn CatalogInput::to_value(self : CatalogInput) -> @rkyv.Value {
  let revision_value = @rkyv.Value::U32(self.revision)
  let products_value_items : Array[@rkyv.Value] = []
  for value in self.products {
    products_value_items.push(value.to_value())
  }
  let products_value = @rkyv.Value::Vec(products_value_items)
  @rkyv.Value::Struct([
    { name: "revision", value: revision_value },
    { name: "products", value: products_value },
  ])
}

///|
pub fn CatalogInput::encode(
  self : CatalogInput,
) -> Bytes raise @rkyv.SchemaError {
  CatalogInput::schema().encode(self.to_value())
}
