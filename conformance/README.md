# Rust / MoonBit conformance contract

This directory makes the release compatibility claim executable. It pins the
Rust oracle to `rkyv = 0.8.17` and uses its default format profile:

- little-endian;
- aligned archives; and
- 32-bit relative pointers and archived `usize` values.

The contract currently covers root `Vec<u32>` and root `String` archives. The
MoonBit test verifies that it produces the canonical Rust bytes. The Rust test
does both the inverse byte comparison and calls `rkyv::access` on bytes encoded
by MoonBit. Consequently, every fixture is checked in both directions.

This is deliberately not a claim that arbitrary `#[derive(Archive)]` types are
interoperable. Struct, tuple, enum, generic collection, and generated-binding
layouts remain outside the published `0.2.0` supported surface.

## Generated binding fixture

The development branch also contains an experimental codegen fixture under
`conformance/generated`. It derives the actual layout of a Rust `User` named
struct (`u32`, `bool`, `String`, and `Vec<u32>`), renders `UserView` as MoonBit
source, and checks that the generated view reads a Rust 0.8.17 archive. Numeric
primitive accessor rendering is tested separately. This fixture is a
development aid only; it does not expand the published `0.2.0` compatibility
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
`Ok(None)`.

Run the complete contract from the repository root:

```sh
just conformance
```
