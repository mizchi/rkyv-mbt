///|
test "finds a Rust-produced product without materializing the catalog" {
  let catalog = validate_catalog_file("examples/catalog/data/catalog.rkyv")
  assert_eq(catalog.revision(), 7U)
  match find_product(catalog, 1002U) {
    None => fail("catalog did not contain product 1002")
    Some(product) => {
      assert_eq(product.name(), "Moon Mug")
      assert_eq(product.price_cents(), 1800U)
      assert_eq(product.stock(), Some(12U))
      let tags = product.tags()
      assert_eq(tags.length(), 2)
      assert_eq(tags.at(0), Some("kitchen"))
      assert_eq(tags.at(1), Some("gift"))
    }
  }
}

///|
test "preserves an unavailable product and reports an absent id" {
  let catalog = open_catalog_file("examples/catalog/data/catalog.rkyv")
  match find_product(catalog, 1003U) {
    None => fail("catalog did not contain product 1003")
    Some(product) => assert_eq(product.stock(), None)
  }
  match find_product(catalog, 9999U) {
    None => ()
    Some(_) => fail("catalog returned a product for an absent id")
  }
}
