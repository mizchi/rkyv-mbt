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

criterion_group!(
    reader,
    bench_lazy_selected_element,
    bench_eager_materialization
);
criterion_main!(reader);
