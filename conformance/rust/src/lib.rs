#[cfg(test)]
use rkyv::{
    Archive, Serialize, access, rancor::Error, string::ArchivedString, to_bytes, util::AlignedVec,
    vec::ArchivedVec,
};

#[cfg(test)]
const VEC_U32: &[u8] = &[
    0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0xf4, 0xff, 0xff, 0xff,
    0x03, 0x00, 0x00, 0x00,
];

#[cfg(test)]
const STRING_INLINE: &[u8] = &[b'm', b'o', b'o', b'n', 0xff, 0xff, 0xff, 0xff];

#[cfg(test)]
const STRING_OUT_OF_LINE: &[u8] = &[
    b'h', b'e', b'l', b'l', b'o', b' ', b'r', b'k', b'y', b'v', 0x00, 0x00, 0x8a, 0x00, 0x00, 0x00,
    0xf4, 0xff, 0xff, 0xff,
];

#[cfg(test)]
const TAGGED_UNION_LABEL: &[u8] = &[
    0x02, 0x00, 0x00, 0x00, b'm', b'i', b'n', b't', 0xff, 0xff, 0xff, 0xff,
];

#[cfg(test)]
#[allow(dead_code)]
#[derive(Archive, Serialize)]
enum HostTaggedUnion {
    Empty,
    Count(u32),
    Label(String),
}

#[test]
fn rust_default_archives_match_the_moonbit_contract() {
    let vec_bytes = to_bytes::<Error>(&vec![1_u32, 2, 3]).expect("serialize Vec<u32>");
    assert_eq!(&*vec_bytes, VEC_U32);

    let inline_bytes = to_bytes::<Error>(&String::from("moon")).expect("serialize inline String");
    assert_eq!(&*inline_bytes, STRING_INLINE);

    let out_of_line_bytes =
        to_bytes::<Error>(&String::from("hello rkyv")).expect("serialize out-of-line String");
    assert_eq!(&*out_of_line_bytes, STRING_OUT_OF_LINE);
}

#[test]
fn rust_accepts_archives_encoded_by_moonbit() {
    let archived_vec = access::<ArchivedVec<u32>, Error>(VEC_U32).expect("accept MoonBit Vec<u32>");
    assert_eq!(archived_vec.as_slice(), [1, 2, 3]);

    let inline_string =
        access::<ArchivedString, Error>(STRING_INLINE).expect("accept MoonBit inline String");
    assert_eq!(inline_string.as_str(), "moon");

    let out_of_line_string = access::<ArchivedString, Error>(STRING_OUT_OF_LINE)
        .expect("accept MoonBit out-of-line String");
    assert_eq!(out_of_line_string.as_str(), "hello rkyv");
}

#[test]
fn rust_and_the_explicit_moonbit_tagged_union_have_the_same_layout() {
    let rust_bytes = to_bytes::<Error>(&HostTaggedUnion::Label("mint".into()))
        .expect("serialize tagged union");
    assert_eq!(&*rust_bytes, TAGGED_UNION_LABEL);

    let mut moon_bytes : AlignedVec<16> = AlignedVec::new();
    moon_bytes.extend_from_slice(TAGGED_UNION_LABEL);
    let value = access::<ArchivedHostTaggedUnion, Error>(&moon_bytes)
        .expect("accept MoonBit tagged union");
    match value {
        ArchivedHostTaggedUnion::Label(label) => assert_eq!(label.as_str(), "mint"),
        _ => panic!("MoonBit tag selected the wrong Rust union variant"),
    }
}
