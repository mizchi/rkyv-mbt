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

conformance:
    moon test
    cargo test --manifest-path conformance/rust/Cargo.toml

info:
    moon info
