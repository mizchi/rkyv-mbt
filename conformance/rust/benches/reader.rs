use criterion::{Criterion, black_box, criterion_group, criterion_main};
use rkyv::{access, rancor::Error, to_bytes, vec::ArchivedVec};

const ELEMENT_COUNT: usize = 4_096;
const SELECTED_INDEX: usize = ELEMENT_COUNT / 2;

fn archive_vec_u32() -> rkyv::util::AlignedVec {
    let values: Vec<u32> = (0..ELEMENT_COUNT as u32).collect();
    to_bytes::<Error>(&values).expect("serialize Vec<u32>")
}

/// rkyv's public safe API performs bytecheck validation before returning the
/// archived root. This matches the MoonBit Reader benchmark's safe path.
fn checked_archived_vec(bytes: &[u8]) -> &ArchivedVec<u32> {
    access::<ArchivedVec<u32>, Error>(bytes).expect("access archived Vec<u32>")
}

/// Matches MoonBit's `read_vec_u32_length`: validate the archived header and
/// complete primitive span, then retain only the logical length.
fn bench_checked_length_validation(criterion: &mut Criterion) {
    let archive = archive_vec_u32();

    criterion.bench_function("Rust rkyv checked length validation / 4K", |bench| {
        bench.iter(|| {
            let archived = checked_archived_vec(black_box(&archive));
            black_box(archived.as_slice().len())
        });
    });
}

/// Matches MoonBit's `U32VecView::get`: validation and view construction are
/// outside the loop, while every iteration performs a bounded lazy element
/// lookup on the retained archived view.
fn bench_validated_selected_element(criterion: &mut Criterion) {
    let archive = archive_vec_u32();
    let archived = checked_archived_vec(&archive);

    criterion.bench_function("Rust rkyv validated lazy selected element / 4K", |bench| {
        bench.iter(|| {
            let index = black_box(SELECTED_INDEX);
            black_box(archived.as_slice().get(index).copied())
        });
    });
}

fn bench_lazy_selected_element(criterion: &mut Criterion) {
    let archive = archive_vec_u32();

    criterion.bench_function("Rust rkyv checked lazy selected element / 4K", |bench| {
        bench.iter(|| {
            let archived = checked_archived_vec(black_box(&archive));
            black_box(archived.as_slice()[SELECTED_INDEX])
        });
    });
}

fn bench_eager_materialization(criterion: &mut Criterion) {
    let archive = archive_vec_u32();

    criterion.bench_function("Rust rkyv checked eager materialization / 4K", |bench| {
        bench.iter(|| {
            let archived = checked_archived_vec(black_box(&archive));
            black_box(archived.as_slice().to_vec())
        });
    });
}

/// Matches MoonBit's `view.copy_into`: validation and view construction are
/// outside the measured loop, while the destination Vec is reused.
fn bench_validated_copy_into_reused_vec(criterion: &mut Criterion) {
    let archive = archive_vec_u32();
    let archived = checked_archived_vec(&archive);
    let mut destination = vec![0_u32; ELEMENT_COUNT];

    criterion.bench_function("Rust rkyv validated copy into reused Vec / 4K", |bench| {
        bench.iter(|| {
            destination.copy_from_slice(black_box(archived.as_slice()));
            black_box(destination[SELECTED_INDEX])
        });
    });
}

/// Matches MoonBit's `Reader::read_vec_u32_into`: checked access occurs on
/// every iteration, but the destination Vec remains allocated by the caller.
fn bench_checked_copy_into_reused_vec(criterion: &mut Criterion) {
    let archive = archive_vec_u32();
    let mut destination = vec![0_u32; ELEMENT_COUNT];

    criterion.bench_function("Rust rkyv checked copy into reused Vec / 4K", |bench| {
        bench.iter(|| {
            let archived = checked_archived_vec(black_box(&archive));
            destination.copy_from_slice(archived.as_slice());
            black_box(destination[SELECTED_INDEX])
        });
    });
}

criterion_group!(
    reader,
    bench_checked_length_validation,
    bench_validated_selected_element,
    bench_lazy_selected_element,
    bench_eager_materialization,
    bench_validated_copy_into_reused_vec,
    bench_checked_copy_into_reused_vec,
);
criterion_main!(reader);
