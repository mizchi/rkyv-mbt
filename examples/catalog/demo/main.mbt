///|
/// Simulates a JavaScript client reading a Rust-built static product catalog.
fn main {
  let catalog = @client.open_catalog_file("examples/catalog/data/catalog.rkyv") catch {
    _ => abort("invalid catalog archive")
  }
  let product = @client.find_product(catalog, 1002U) catch {
    _ => abort("invalid catalog products")
  }
  match product {
    None => abort("Moon Mug was not found")
    Some(product) => {
      let name = product.name() catch { _ => abort("invalid product name") }
      let price = product.price_cents() catch {
        _ => abort("invalid product price")
      }
      println("\{name}: \{price} cents")
    }
  }
}
