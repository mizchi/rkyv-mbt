use rkyv::{Archive, Serialize, rancor::Error, to_bytes};
use rkyv_mbt_codegen::{FieldKind, RkyvMbt, write_moonbit};
use rkyv_mbt_derive::RkyvMbt;

#[derive(Archive, Serialize, RkyvMbt)]
pub struct User {
    pub id: u32,
    pub active: bool,
    pub name: String,
    pub scores: Vec<u32>,
}

#[derive(Archive, Serialize, RkyvMbt)]
pub struct Metrics {
    pub delta: i64,
    pub ratio: f32,
    pub total: u64,
}

#[derive(Archive, Serialize, RkyvMbt)]
pub struct Profile {
    pub age: u32,
    pub subscribed: bool,
}

#[derive(Archive, Serialize, RkyvMbt)]
pub struct Account {
    pub id: u32,
    pub profile: Profile,
}

#[derive(Archive, Serialize, RkyvMbt)]
pub struct Preferences {
    pub retries: Option<u32>,
    pub nickname: Option<String>,
    pub profile: Option<Profile>,
}

#[derive(Archive, Serialize, RkyvMbt)]
pub struct Directory {
    pub entries: Vec<Profile>,
}

#[test]
fn derives_the_archived_struct_layout_and_moonbit_view() {
    let schema = User::rkyv_mbt_schema();

    assert_eq!(schema.name, "User");
    assert_eq!(schema.archived_size, 24);
    assert_eq!(
        schema.fields,
        vec![
            ("id".into(), 0, FieldKind::U32),
            ("active".into(), 4, FieldKind::Bool),
            ("name".into(), 8, FieldKind::String),
            ("scores".into(), 16, FieldKind::VecU32),
        ],
    );
    assert_eq!(
        schema.render_moonbit(),
        include_str!("../../../../conformance/generated/user.mbt"),
    );
}

#[test]
fn archives_a_codegen_fixture_for_moonbit() {
    let archive = to_bytes::<Error>(&User {
        id: 42,
        active: true,
        name: "Ada".into(),
        scores: vec![7, 11, 13],
    })
    .expect("archive User");

    assert_eq!(
        &*archive,
        &[
            7, 0, 0, 0, 11, 0, 0, 0, 13, 0, 0, 0, 42, 0, 0, 0, 1, 0, 0, 0, 65, 100, 97, 255, 255,
            255, 255, 255, 228, 255, 255, 255, 3, 0, 0, 0,
        ],
    );
}

#[test]
fn writes_the_generated_moonbit_source() {
    let output = std::env::temp_dir().join(format!(
        "rkyv-mbt-codegen-user-{}-{}.mbt",
        std::process::id(),
        std::thread::current().name().unwrap_or("schema"),
    ));

    write_moonbit::<User>(&output).expect("write MoonBit binding");
    assert_eq!(
        std::fs::read_to_string(output).expect("read generated MoonBit binding"),
        User::rkyv_mbt_schema().render_moonbit(),
    );
}

#[test]
fn generates_all_supported_numeric_primitive_accessors() {
    let schema = Metrics::rkyv_mbt_schema();

    assert_eq!(schema.archived_size, 24);
    assert_eq!(
        schema.fields,
        vec![
            ("delta".into(), 0, FieldKind::I64),
            ("ratio".into(), 8, FieldKind::F32),
            ("total".into(), 16, FieldKind::U64),
        ],
    );
    let source = schema.render_moonbit();
    assert!(source.contains("Result[Int64, @rkyv.RkyvError]"));
    assert!(source.contains("self.reader.read_i64(self.offset)"));
    assert!(source.contains("Result[Float, @rkyv.RkyvError]"));
    assert!(source.contains("self.reader.read_f32(self.offset + 8)"));
    assert!(source.contains("Result[UInt64, @rkyv.RkyvError]"));
    assert!(source.contains("self.reader.read_u64(self.offset + 16)"));
}

#[test]
fn generates_a_nested_struct_view_from_the_archived_layout() {
    let profile = Profile::rkyv_mbt_schema();
    assert_eq!(profile.archived_size, 8);
    assert_eq!(
        profile.fields,
        vec![
            ("age".into(), 0, FieldKind::U32),
            ("subscribed".into(), 4, FieldKind::Bool),
        ],
    );
    assert_eq!(
        profile.render_moonbit(),
        include_str!("../../../../conformance/generated/profile.mbt"),
    );

    let account = Account::rkyv_mbt_schema();
    assert_eq!(account.archived_size, 12);
    assert_eq!(
        account.fields,
        vec![
            ("id".into(), 0, FieldKind::U32),
            ("profile".into(), 4, FieldKind::Struct("Profile".into())),
        ],
    );
    let source = account.render_moonbit();
    assert!(source.contains("ProfileView::at(self.reader, self.offset + 4)"));
    assert_eq!(
        source,
        include_str!("../../../../conformance/generated/account.mbt"),
    );
}

#[test]
fn archives_a_nested_struct_fixture_for_moonbit() {
    let archive = to_bytes::<Error>(&Account {
        id: 99,
        profile: Profile {
            age: 33,
            subscribed: true,
        },
    })
    .expect("archive Account");

    assert_eq!(&*archive, &[99, 0, 0, 0, 33, 0, 0, 0, 1, 0, 0, 0]);
}

#[test]
fn generates_optional_values_from_the_archived_layout() {
    let schema = Preferences::rkyv_mbt_schema();

    assert_eq!(schema.archived_size, 32);
    assert_eq!(
        schema.fields,
        vec![
            (
                "retries".into(),
                0,
                FieldKind::Option(Box::new(FieldKind::U32), 4),
            ),
            (
                "nickname".into(),
                8,
                FieldKind::Option(Box::new(FieldKind::String), 4),
            ),
            (
                "profile".into(),
                20,
                FieldKind::Option(Box::new(FieldKind::Struct("Profile".into())), 4),
            ),
        ],
    );
    let source = schema.render_moonbit();
    assert!(source.contains("Result[UInt?, @rkyv.RkyvError]"));
    assert!(source.contains("read_option_value_offset(self.offset, 4)"));
    assert!(source.contains("Result[ProfileView?, @rkyv.RkyvError]"));
    assert_eq!(
        source,
        include_str!("../../../../conformance/generated/preferences.mbt"),
    );
}

#[test]
fn archives_optional_values_for_moonbit() {
    let archive = to_bytes::<Error>(&Preferences {
        retries: None,
        nickname: Some("Lin".into()),
        profile: Some(Profile {
            age: 9,
            subscribed: true,
        }),
    })
    .expect("archive Preferences");

    assert_eq!(
        &*archive,
        &[
            0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 76, 105, 110, 255, 255, 255, 255, 255, 1, 0, 0, 0,
            9, 0, 0, 0, 1, 0, 0, 0,
        ],
    );
}

#[test]
fn generates_a_lazy_view_for_a_vector_of_nested_structs() {
    let schema = Directory::rkyv_mbt_schema();

    assert_eq!(schema.archived_size, 8);
    assert_eq!(
        schema.fields,
        vec![(
            "entries".into(),
            0,
            FieldKind::VecStruct("Profile".into(), 8),
        )],
    );
    let source = schema.render_moonbit();
    assert!(source.contains("pub struct DirectoryEntriesView"));
    assert!(source.contains("read_vec_header_with_element_size(self.offset, 8)"));
    assert!(source.contains("ProfileView::at(self.reader, self.data_offset + index * 8)"));
    assert_eq!(
        source,
        include_str!("../../../../conformance/generated/directory.mbt"),
    );
}

#[test]
fn archives_a_vector_of_nested_structs_for_moonbit() {
    let archive = to_bytes::<Error>(&Directory {
        entries: vec![
            Profile {
                age: 4,
                subscribed: true,
            },
            Profile {
                age: 9,
                subscribed: false,
            },
        ],
    })
    .expect("archive Directory");

    assert_eq!(
        &*archive,
        &[
            4, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 240, 255, 255, 255, 2, 0, 0, 0,
        ],
    );
}
