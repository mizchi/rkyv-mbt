///|
/// Opens the Rust-produced binary catalog archive from a local Node path.
pub fn open_catalog_file(
  path : String,
) -> @catalog.CatalogView raise @rkyv.RkyvError {
  @catalog.CatalogView::root(@runtime.read_binary(path))
}

///|
/// Opens a catalog received from an untrusted source. This traverses every
/// generated field before returning the same zero-copy view shape as `root`.
pub fn validate_catalog_file(
  path : String,
) -> @catalog.CatalogView raise @rkyv.RkyvError {
  @catalog.CatalogView::validate(@runtime.read_binary(path))
}

///|
/// Searches the archived product list lazily. No MoonBit `Array` of products
/// is allocated while scanning the catalog.
pub fn find_product(
  catalog : @catalog.CatalogView,
  id : UInt,
) -> @catalog.ProductView? raise @rkyv.RkyvError {
  let products = catalog.products()
  let mut index = 0
  while index < products.length() {
    match products.at(index) {
      None => ()
      Some(product) => if product.id() == id { return Some(product) }
    }
    index = index + 1
  }
  None
}
