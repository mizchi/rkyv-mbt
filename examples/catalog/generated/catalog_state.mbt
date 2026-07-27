///|
pub enum CatalogStateTag {
  Draft
  Published
  Retired
} derive(Debug, Eq)

///|
pub struct CatalogStateView {
  reader : @rkyv.Reader
  offset : Int
}

///|
pub fn CatalogStateView::at(
  reader : @rkyv.Reader,
  offset : Int,
) -> CatalogStateView raise @rkyv.RkyvError {
  reader.validate_range(offset, 1)
  { reader, offset }
}

///|
pub fn CatalogStateView::root(bytes : Bytes) -> CatalogStateView raise @rkyv.RkyvError {
  let reader = @rkyv.Reader::new(bytes)
  let offset = reader.root_offset(1)
  CatalogStateView::at(reader, offset)
}

///|
pub fn CatalogStateView::validate(bytes : Bytes) -> CatalogStateView raise @rkyv.RkyvError {
  let view = CatalogStateView::root(bytes)
  let _ = view.tag()
  view
}

///|
pub fn CatalogStateView::tag(self : CatalogStateView) -> CatalogStateTag raise @rkyv.RkyvError {
  let value = self.reader.read_union_tag(self.offset, [b'\x00', b'\x01', b'\x02'])
  match value {
    b'\x00' => CatalogStateTag::Draft
    b'\x01' => CatalogStateTag::Published
    b'\x02' => CatalogStateTag::Retired
    _ => abort("validated enum tag was not matched")
  }
}

///|
pub(all) enum CatalogStateInput {
  Draft
  Published
  Retired
}

///|
pub fn CatalogStateInput::schema() -> @rkyv.Schema {
  @rkyv.Schema::TaggedUnion(
    [
      { name: "Draft", tag: b'\x00', schema: @rkyv.Schema::Struct([]) },
      { name: "Published", tag: b'\x01', schema: @rkyv.Schema::Struct([]) },
      { name: "Retired", tag: b'\x02', schema: @rkyv.Schema::Struct([]) },
    ],
    0,
    0,
    1,
  )
}

///|
pub fn CatalogStateInput::to_value(self : CatalogStateInput) -> @rkyv.Value {
  match self {
    CatalogStateInput::Draft => @rkyv.Value::Tagged(b'\x00', None)
    CatalogStateInput::Published => @rkyv.Value::Tagged(b'\x01', None)
    CatalogStateInput::Retired => @rkyv.Value::Tagged(b'\x02', None)
  }
}

///|
pub fn CatalogStateInput::encode(self : CatalogStateInput) -> Bytes raise @rkyv.SchemaError {
  CatalogStateInput::schema().encode(self.to_value())
}
