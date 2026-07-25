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
layouts remain outside the package's supported surface until code generation is
implemented.

Run the complete contract from the repository root:

```sh
just conformance
```
