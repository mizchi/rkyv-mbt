///|
/// Produces an rkyv `Catalog` archive entirely from MoonBit's generated typed
/// input API. The Rust example verifies this file in `just catalog-roundtrip`.
fn main {
  let first = @catalog.ProductInput::new(2001U, 450U, Some(9U), "Moon Plate", [
    "kitchen", "blue",
  ])
  let second = @catalog.ProductInput::new(2002U, 900U, None, "Bag", ["gift"])
  let archive = @catalog.CatalogInput::new(8U, [first, second]).encode() catch {
    _ => abort("generated Catalog input did not match its schema")
  }
  @runtime.write_binary("_build/catalog-moonbit.rkyv", archive)
  let telemetry = @catalog.TelemetryInput::new(
    [-7, 12, 1024],
    [1.5, -2.25],
    Some(["fast", "cold"]),
    Some([-1, 7]),
  ).encode() catch {
    _ => abort("generated Telemetry input did not match its schema")
  }
  @runtime.write_binary("_build/telemetry-moonbit.rkyv", telemetry)
  let state = @catalog.CatalogStateInput::Published.encode() catch {
    _ => abort("generated CatalogState input did not match its schema")
  }
  @runtime.write_binary("_build/catalog-state-moonbit.rkyv", state)
  println("wrote MoonBit Catalog archive")
}
