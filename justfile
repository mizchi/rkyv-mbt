default:
    @just --list

fmt:
    moon fmt

check:
    moon check

test:
    moon test

bench:
    moon bench --release

bench-moonbit-native:
    moon bench --release --target native

bench-profile:
    moon bench --release --target native reader_bench.mbt

profile:
    moon run --profile --release --target native cmd/profile

host-schema:
    moon run examples/host_codegen/user_schema.mbtx > examples/host_codegen/generated/user.mbt

check-host-schema:
    moon run examples/host_codegen/user_schema.mbtx | diff - examples/host_codegen/generated/user.mbt

host-js: check-host-schema
    moon run --target js cmd/host_js

catalog-generate:
    cargo run --manifest-path examples/catalog/rust/Cargo.toml

check-catalog:
    cargo run --manifest-path examples/catalog/rust/Cargo.toml -- --check

catalog-js: check-catalog
    moon run --target js examples/catalog/demo

catalog-roundtrip: check-catalog
    moon run --target js examples/catalog/roundtrip
    cargo run --manifest-path examples/catalog/rust/Cargo.toml -- --verify-moonbit _build/catalog-moonbit.rkyv
    cargo run --manifest-path examples/catalog/rust/Cargo.toml -- --verify-telemetry _build/telemetry-moonbit.rkyv
    cargo run --manifest-path examples/catalog/rust/Cargo.toml -- --verify-state _build/catalog-state-moonbit.rkyv

bench-rust:
    cargo bench --manifest-path conformance/rust/Cargo.toml

bench-compare:
    just bench-moonbit-native
    just bench-rust

conformance:
    just check-host-schema
    just check-catalog
    just catalog-roundtrip
    moon test
    cargo test --manifest-path conformance/rust/Cargo.toml
    cargo test --workspace

codegen:
    cargo test --workspace

info:
    moon info
