# Rust / MoonBit conformance contract

This directory makes the release compatibility claim executable. It pins the
Rust oracle to `rkyv = 0.8.17` and uses its default format profile:

- little-endian;
- aligned archives; and
- 32-bit relative pointers and archived `usize` values.

The base fixtures cover root `Vec<u32>` and root `String` archives. The
MoonBit test verifies that it produces the canonical Rust bytes. The Rust test
does both the inverse byte comparison and calls `rkyv::access` on bytes encoded
by MoonBit. An explicit `#[repr(u8)]`-style tagged union fixture additionally
proves the shared `tag + padding + inline String` layout in both directions.

This is deliberately not a claim that arbitrary `#[derive(Archive)]` types are
interoperable. Tuple structs, maps, generic collections, and payload-enum
codegen layouts remain outside the supported surface. Generated named structs,
primitive vectors, one-level options, and fieldless enums are covered by the
end-to-end catalog checks below.

## Generated binding fixture

The development branch also contains an experimental codegen fixture under
`conformance/generated`. It derives the actual layout of a Rust `User` named
struct (`u32`, `bool`, `String`, and `Vec<u32>`), renders `UserView` as MoonBit
source, and checks that the generated view reads a Rust 0.8.17 archive. Numeric
primitive accessor rendering is tested separately. This fixture is a
development aid only; it does not expand the published `0.3.0` compatibility
promise.

An additional `Account { id, profile }` fixture verifies generated nested
views. `AccountView::profile()` validates and returns an inline `ProfileView`
over the same archive bytes without copying.

`Preferences` covers generated `Option<T>` accessors: `None`, inline
`Some(String)`, and `Some(Profile)`. The schema records Rust's archived inner
alignment and MoonBit resolves the `ArchivedOption` tag and padding through the
runtime rather than duplicating those layout rules in each binding.

`Directory { entries: Vec<Profile> }` covers generated lazy collection views.
Its Rust fixture contains two archived `Profile` values followed by the rkyv
vector header. MoonBit validates the complete fixed-size element span before
returning `DirectoryEntriesView`, then validates and reads only the requested
element through `ProfileView::at`. Negative and past-the-end indices return
`None`.

The catalog example is the write-side integration fixture. Its `Telemetry`
binding exercises `Vec<i16>`, `Vec<f64>`, `Option<Vec<String>>`, and
`Option<Vec<i16>>`; MoonBit encodes each value and Rust accepts it through
`rkyv::access`. `CatalogState` does the same for a fieldless enum. These checks
run as part of `just catalog-roundtrip`.

Run the complete contract from the repository root:

```sh
just conformance
```
