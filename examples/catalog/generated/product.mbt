///|
pub struct ProductView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn ProductView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> ProductView raise @rkyv.RkyvError {
  reader.validate_range(offset, 32)
  { reader, offset }
}

///|
pub fn ProductView::root(bytes : Bytes) -> ProductView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(32)
  ProductView::at(reader, offset)
}

///|
pub fn ProductView::validate(
  bytes : Bytes,
) -> ProductView raise @rkyv.RkyvError {
  let view = ProductView::root(bytes)
  view.validate_all(256)
  view
}

///|
pub fn ProductView::validate_all(
  self : ProductView,
  remaining_depth : Int,
) -> Unit raise @rkyv.RkyvError {
  @rkyv.require_validation_depth(remaining_depth)
  let _ = self.reader.read_u32(self.offset)
  let _ = self.reader.read_u32(self.offset + 4)
  match self.reader.read_option_value_offset_strict(self.offset + 8, 4) {
    None => ()
    Some(value_offset) => {
      let _ = self.reader.read_u32(value_offset)
    }
  }
  let _ = self.reader.read_string(self.offset + 16)
  let values = self.tags()
  for index in 0..<values.length() {
    let _ = values.at(index)
  }
}

///|
pub fn ProductView::id(self : ProductView) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset)
}

///|
pub fn ProductView::price_cents(
  self : ProductView,
) -> UInt raise @rkyv.RkyvError {
  self.reader.read_u32(self.offset + 4)
}

///|
pub fn ProductView::stock(self : ProductView) -> UInt? raise @rkyv.RkyvError {
  match self.reader.read_option_value_offset(self.offset + 8, 4) {
    None => None
    Some(value_offset) => Some(self.reader.read_u32(value_offset))
  }
}

///|
pub fn ProductView::name(self : ProductView) -> String raise @rkyv.RkyvError {
  self.reader.read_string(self.offset + 16)
}

///|
pub fn ProductView::tags(
  self : ProductView,
) -> ProductTagsView raise @rkyv.RkyvError {
  let header = self.reader.read_vec_header_with_element_size(
    self.offset + 24,
    8,
  )
  {
    reader: self.reader,
    data_offset: header.data_offset,
    length: header.length,
  }
}

///|
pub struct ProductTagsView {
  reader : @rkyv.Reader
  data_offset : Int
  length : Int
}

///|
pub fn ProductTagsView::length(self : ProductTagsView) -> Int {
  self.length
}

///|
pub fn ProductTagsView::at(
  self : ProductTagsView,
  index : Int,
) -> String? raise @rkyv.RkyvError {
  if index < 0 || index >= self.length {
    None
  } else {
    Some(self.reader.read_string(self.data_offset + index * 8))
  }
}

///|
pub struct ProductInput {
  id : UInt
  price_cents : UInt
  stock : UInt?
  name : String
  tags : Array[String]
}

///|
pub fn ProductInput::new(
  id : UInt,
  price_cents : UInt,
  stock : UInt?,
  name : String,
  tags : Array[String],
) -> ProductInput {
  { id, price_cents, stock, name, tags }
}

///|
pub fn ProductInput::schema() -> @rkyv.Schema {
  @rkyv.Schema::StructLayout(
    [
      { name: "id", schema: @rkyv.Schema::U32 },
      { name: "price_cents", schema: @rkyv.Schema::U32 },
      { name: "stock", schema: @rkyv.Schema::Option(@rkyv.Schema::U32) },
      { name: "name", schema: @rkyv.Schema::String },
      { name: "tags", schema: @rkyv.Schema::Vec(@rkyv.Schema::String) },
    ],
    [0, 4, 8, 16, 24],
    32,
  )
}

///|
pub fn ProductInput::to_value(self : ProductInput) -> @rkyv.Value {
  let id_value = @rkyv.Value::U32(self.id)
  let price_cents_value = @rkyv.Value::U32(self.price_cents)
  let stock_value = match self.stock {
    None => @rkyv.Value::Option(None)
    Some(value) => {
      let stock_value_some = @rkyv.Value::U32(value)
      @rkyv.Value::Option(Some(stock_value_some))
    }
  }
  let name_value = @rkyv.Value::String(self.name)
  let tags_value_items : Array[@rkyv.Value] = []
  for value in self.tags {
    tags_value_items.push(@rkyv.Value::String(value))
  }
  let tags_value = @rkyv.Value::Vec(tags_value_items)
  @rkyv.Value::Struct([
    { name: "id", value: id_value },
    { name: "price_cents", value: price_cents_value },
    { name: "stock", value: stock_value },
    { name: "name", value: name_value },
    { name: "tags", value: tags_value },
  ])
}

///|
pub fn ProductInput::encode(
  self : ProductInput,
) -> Bytes raise @rkyv.SchemaError {
  ProductInput::schema().encode(self.to_value())
}
