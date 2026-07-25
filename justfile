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

bench-rust:
    cargo bench --manifest-path conformance/rust/Cargo.toml

bench-compare:
    just bench-moonbit-native
    just bench-rust

conformance:
    moon test
    cargo test --manifest-path conformance/rust/Cargo.toml
    cargo test --workspace

codegen:
    cargo test --workspace

info:
    moon info
