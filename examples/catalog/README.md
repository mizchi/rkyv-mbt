# Static product catalog

This is an end-to-end rkyv use case rather than a hand-written byte fixture.
A Rust build step owns the `Product` and `Catalog` types, serializes a static
catalog with rkyv, and derives the exact archived field layout. It writes:

- typed MoonBit bindings for `ProductView` / `CatalogView` and their matching
  `ProductInput` / `CatalogInput`; and
- a checked-in `data/catalog.rkyv` binary for the Rust-produced archive.

The minimal Node runtime passes `readFileSync`'s `Buffer` directly as MoonBit
`Bytes`; it does not copy the archive before opening it. The MoonBit client
then scans `Vec<Product>` lazily. It does not parse JSON or materialize a
MoonBit product array; a `ProductView` is constructed only for the element
currently inspected. `CatalogView::validate` is available at an untrusted
archive boundary and traverses the generated schema before exposing the view.

```sh
just catalog-generate
just check-catalog
just catalog-js
# Moon Mug: 1800 cents
just catalog-roundtrip
```

`catalog-roundtrip` constructs a different catalog through the generated typed
MoonBit inputs, writes it as a binary archive, then has Rust validate it with
`rkyv::access` and assert its nested products, tags, and optional stock values.

Use the generated files as build artifacts. Check them in so the JavaScript
client can compile without a Rust toolchain, and run the Rust generator in CI
to ensure they remain synchronized with the Rust type definitions.
