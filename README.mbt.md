# mizchi/rkyv

[日本語](README.ja.md)

A small, safe MoonBit runtime and encoder for rkyv 0.8 archives. It reads a
Rust-produced archive without copying it, while keeping schema-specific code in
generated bindings or application code.

The design follows the split used by
[cometkim/rkyv-js](https://github.com/cometkim/rkyv-js): a shared wire-format
runtime plus bindings generated from Rust types.

## Release contract

The supported wire-format contract is rkyv **0.8.17** with its default format:

- little-endian;
- aligned archives; and
- 32-bit relative pointers and archived `usize` values.

The executable compatibility contract covers the checked reader primitives,
host-defined scalar/vector/option/tagged-union schemas, and the generated
catalog bindings. See [conformance/README.md](conformance/README.md) for the
exact fixtures and limits.

## Features

- Bounds-checked reader for the default rkyv format.
- Bit-compatible `u8`–`u64`, `i8`–`i64`, `f32`, `f64`, and `bool` reads.
- Relative pointers, `ArchivedVec<T>` headers, and `ArchivedOption<T>` value
  offsets.
- A bounds-checked, zero-copy `BytesView` for raw archive ranges.
- A zero-copy `ArchivedVec<u32>` view with lazy access, `Array`/
  `FixedArray` materialization, and caller-owned buffer copies.
- Default-format schema-directed encoders for primitives, strings, vectors,
  options, structs, and explicit tagged unions.
- Little- and big-endian primitive readers with 16-, 32-, or 64-bit pointers.
- Experimental Rust code generation for typed MoonBit views of named structs.
- Experimental MoonBit-owned schemas for Rust-free default-format encoding and
  schema-directed zero-copy views, including the JavaScript target.
- Optional `RMBT` v1 envelopes with format flags, payload length, CRC-32, and
  a caller-provided payload limit for untrusted transport data.

## Usage

```moonbit nocheck
import {
  "mizchi/rkyv" @rkyv,
}

let reader = @rkyv.Reader::new(archive_bytes)
let view = reader.read_vec_u32(archive_bytes.length() - 8) catch {
  error => abort("invalid rkyv archive: \{error}")
}
```

All fallible reader and generated-view APIs raise `RkyvError`. `View::root` is
the lazy path for trusted archives. For an untrusted archive generated Rust
views also provide `View::validate(bytes)`: it traverses every supported field,
checks pointers, collection spans, UTF-8, canonical bool/`Option`/enum tags, and
limits recursive traversal to 256 levels before returning the same zero-copy
view. It is deliberately scoped to the generated supported types and is not a
drop-in replacement for Rust `bytecheck` on arbitrary rkyv types.

### Transport envelope

For bytes received from a file, network, or cache, wrap the ordinary rkyv
payload in an optional `RMBT` v1 envelope. It records the selected rkyv format,
payload length, and CRC-32; `decode_envelope_with_limit` rejects an excessive
declared payload before copying it. After checking the envelope, pass its
payload to the generated validator.

```moonbit nocheck
///|
let envelope = @rkyv.encode_envelope(archive)

///|
let decoded = @rkyv.decode_envelope_with_limit(envelope, 16 * 1024 * 1024) catch {
  error => abort("invalid archive transport: \{error}")
}

///|
let view = @catalog.CatalogView::validate(decoded.payload_bytes()) catch {
  error => abort("invalid rkyv archive: \{error}")
}
```

The primary collection APIs are `read_vec_u32`, `read_vec_u32_length`,
`read_vec_u32_into`, and `U32VecView::copy_into`. They validate first and do
not allocate an error wrapper on a successful read:

```moonbit nocheck
///|
let view = reader.read_vec_u32(root_offset) catch {
  error => abort("invalid rkyv archive: \{error}")
}

///|
let selected = view.get(index)
```

Use `try`/`catch` when a caller needs local recovery. `U32VecView::get` and
`U32VecView::at` return `None` only for an out-of-range logical index; archive
validation failures always raise `RkyvError`.

`reader.read_bytes_view(offset, length)` returns a zero-copy `BytesView` after
checking only the requested range. It does not validate a higher-level rkyv
layout or UTF-8; use `read_string` when a decoded, validated `String` is
needed.

## Generated MoonBit schemas and JavaScript

Use an `.mbtx` script as the source of truth, generate a typed MoonBit package,
then import that package from the client. This keeps the dynamic `Schema` /
`Value` representation out of application code while still using no Rust.

### Direct host-defined schema API

For a small or one-off archive, define the schema directly in MoonBit. The
field declaration order in `Schema::Struct` is the archive layout contract.
`Value::Struct` checks both the field count and names before encoding, and
raises `SchemaError` if it does not match the schema.

This direct form is runtime-checked because field names and schemas are values.
Use the generated API below when callers need compile-time field and value
types.

```moonbit nocheck
///|
let user = @rkyv.Schema::Struct([
  { name: "id", schema: @rkyv.Schema::U32 },
  { name: "active", schema: @rkyv.Schema::Bool },
  { name: "name", schema: @rkyv.Schema::String },
  { name: "scores", schema: @rkyv.Schema::VecU32 },
])

///|
let archive = user.encode(
  @rkyv.Value::Struct([
    { name: "id", value: @rkyv.Value::U32(42U) },
    { name: "active", value: @rkyv.Value::Bool(true) },
    { name: "name", value: @rkyv.Value::String("Ada") },
    { name: "scores", value: @rkyv.Value::VecU32([7U, 11U, 13U]) },
  ]),
) catch {
  _ => abort("schema and value do not match")
}
```

`root` opens a schema-directed zero-copy `View`. Accessing the vector does not
materialize an `Array` unless the caller asks for one:

```moonbit nocheck
///|
let root = user.root(archive) catch { _ => abort("invalid archive") }

///|
let name = root.field("name")

///|
let scores = root.field("scores")
```

### In-place archive updates

Use `encode_mut` when the archive buffer must remain caller-owned. `root_mut`
validates the root and provides `MutView` setters that never relocate data:
`set_u32`, `set_bool`, `set_string` with the same UTF-8 byte length, and
`vec_u32_mut().set` for an existing vector index. Changing a string or vector
length still requires re-encoding the archive.

```moonbit nocheck
///|
let archive = user.encode_mut(
  @rkyv.Value::Struct([
    { name: "id", value: @rkyv.Value::U32(42U) },
    { name: "active", value: @rkyv.Value::Bool(true) },
    { name: "name", value: @rkyv.Value::String("Ada") },
    { name: "scores", value: @rkyv.Value::VecU32([7U, 11U, 13U]) },
  ]),
)

///|
let root = user.root_mut(archive.mut_view())

///|
match root.field("id") {
  Some(id) => ignore(id.set_u32(99U))
  None => abort("missing id")
}

///|
match root.field("scores") {
  Some(scores) => match scores.vec_u32_mut() {
    Some(scores) => ignore(scores.set(1, 42U))
    None => abort("scores is not Vec<u32>")
  }
  None => abort("missing scores")
}
```

[`examples/host_codegen/user_schema.mbtx`](examples/host_codegen/user_schema.mbtx)
declares the input schema and renders
[`examples/host_codegen/generated/user.mbt`](examples/host_codegen/generated/user.mbt):

```moonbit nocheck
///|
let user = {
  name: "User",
  fields: [
    { name: "id", typ: UInt32 },
    { name: "active", typ: Bool },
    { name: "name", typ: Text },
    { name: "scores", typ: UInt32Array },
  ],
}
emit_schema(user)
```

The JavaScript client imports only the generated API. It receives schema-specific
`UserView` and `UserMutView` types: callers cannot pass a field name, and the
type of every getter and setter is fixed by the source schema.
`encode` always returns caller-owned `Array[Byte]`; convert it explicitly with
`Bytes::from_array` when opening a read-only view.

```moonbit nocheck
///|
import {
  "mizchi/rkyv/examples/host_codegen/generated" @user,
}

///|
let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U])

///|
let root = @user.UserView::root(Bytes::from_array(archive))

///|
let name : String = root.name()

///|
let scores : @rkyv.U32VecView = root.scores()
```

For an in-place update, the generated mutable view exposes only valid setters:

```moonbit nocheck
///|
let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U])

///|
let writer = @user.UserMutView::root(archive.mut_view())

///|
writer.set_id(99U)
writer.set_active(false)
let patched : Bool = writer.set_name_same_length("Eve")
let scores = writer.scores_mut()
ignore(scores.set(1, 42U))
```

Regenerate after changing the source schema. `host-js` first confirms that the
checked-in generated source is current, then runs the client entirely under the
JS target:

```sh
just host-schema
just host-js
# Eve: 3 scores
```

The current generator supports `u32`, `bool`, `String`, and `Vec<u32>` fields.
Field declaration order is the layout contract. It does not infer arbitrary
Rust `Archived<T>` field offsets; for a schema shared with an existing Rust
type, verify its bytes against Rust or use the Rust layout codegen path.

## Dogfooding: static product catalog

[`examples/catalog`](examples/catalog) is an end-to-end, production-shaped
example. A Rust build step owns `Catalog { products: Vec<Product> }`, archives
real catalog data with rkyv, and uses `RkyvMbt` to generate the exact MoonBit
views. The JavaScript-target client opens the checked-in `.rkyv` binary through
a minimal Node `Buffer -> Bytes` loader, then searches the `Vec<Product>`
lazily without parsing JSON or materializing a product array.

The generated package also contains `ProductInput` and `CatalogInput`. Their
constructors make the MoonBit-to-Rust path type-safe for this schema, including
`Vec<Product>`, `Vec<String>`, and `Option<u32>`.

```sh
just catalog-generate
moon test --target js examples/catalog/client
just catalog-js
# Moon Mug: 1800 cents
just catalog-roundtrip
```

`check-catalog`, which is included in `just conformance`, verifies that the
Rust types, generated views, and archive fixture remain synchronized.
`catalog-roundtrip` writes a catalog through `CatalogInput::encode()` in
MoonBit, then validates and inspects it with Rust `rkyv::access`.

## Benchmarks

Native release results for a 4,096-element `Vec<u32>`. The archive is built
once outside each measured iteration. MoonBit numbers are benchmark means;
Rust numbers are Criterion 95% confidence intervals, so treat this as an
end-to-end comparison rather than a precise instruction-level comparison.

Environment: arm64, macOS 26.5.2, Moon 0.1.20260713 / moonc 0.10.4, Rust
1.96.0, and rkyv 0.8.17.

| Operation | MoonBit native | Rust rkyv native |
| --- | ---: | ---: |
| Checked header + length validation | **6.33 ns** | 3.01 ns |
| Validated lazy selected element | **6.84 ns** | 1.44 ns |
| Checked root + selected lazy element | **9.81 ns** | 3.32 ns |
| Checked eager materialization of all 4K elements | 478.40 ns | 256.22 ns |
| Copy from a validated view to a reused `FixedArray` / Rust `Vec` | 200.39 ns | 200.15 ns |
| Checked copy to a reused `FixedArray` / Rust `Vec` | **198.22 ns** | 201.11 ns |
| Copy to a reused `MutArrayView` | 1.50 µs | — |

The Rust comparison uses `rkyv::access`, its public checked API. Both sides
receive the same already-encoded 4K `Vec<u32>` archive; archive construction is
outside every timed loop. MoonBit uses `--target native`; target runtimes,
allocation strategy, and compiler optimization are all included in these
numbers. Re-run on the target system before making a deployment decision:

```sh
just bench
just bench-profile
just bench-compare
just profile
just host-js
```

For throughput-sensitive code, retain a `U32VecView` for repeated `get` calls,
use `FixedArray` with `copy_into` for reused storage, and prefer
`to_fixed_array_fast()` to `to_array_fast()` when a growable `Array` is not
required. `MutArrayView` keeps a convenient subrange but is not the native
bulk-copy path.

## Rust interoperability

`just conformance` verifies both directions byte-for-byte:

- MoonBit reads bytes generated by Rust `rkyv::to_bytes`.
- Rust `rkyv::access` accepts bytes generated by MoonBit `encode_vec_u32` and
  `encode_string`.
- The catalog example proves generated MoonBit-to-Rust archives for nested
  structs, primitive vectors, `Vec<String>`, `Option<Vec<T>>`, and fieldless
  enums.

Arbitrary `#[derive(Archive)]` structs, tuples, enums, generic collections,
and general `Vec<T>` are outside this published compatibility guarantee.

## Experimental typed code generation

`codegen/rust` contains `RkyvMbt`, a Rust derive that asks the Rust compiler for
the concrete `Archived<T>` size and field offsets, then renders a typed MoonBit
view. It supports named structs with numeric primitives, `bool`, `String`,
`Vec<primitive>`, `Vec<String>`, nested derive-enabled named structs, their
vectors, and one-level `Option<T>` including `Option<Vec<T>>`. Fieldless enums
generate a strict tag view and a type-safe writer through `RkyvMbtEnum`.

`render_moonbit_with_encoder()` additionally generates `TypeInput::new` and
`TypeInput::encode` for every supported struct field. The generated writer uses
the Rust compiler's exact field offsets and `Archived<T>` size rather than
recomputing struct layout from field declaration order.

The Rust crates are experimental and are not published to crates.io. See
[codegen/rust/README.md](codegen/rust/README.md) for the supported profile and
usage.

## Development

```sh
just fmt
just check
just test
just conformance
just codegen
```

## License

Apache-2.0. See [LICENSE](LICENSE).
