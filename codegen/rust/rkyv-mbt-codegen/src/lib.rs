//! Rust-side schema extraction and MoonBit binding rendering for rkyv archives.

use std::{fmt::Write, path::Path};

/// A field type currently understood by the MoonBit rkyv runtime.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FieldKind {
    U8,
    U16,
    U32,
    U64,
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    Bool,
    String,
    VecU32,
    VecStruct(String, usize),
    Struct(String),
    Option(Box<FieldKind>, usize),
}

/// The rkyv layout that a generated MoonBit view needs to access a struct.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StructSchema {
    pub name: String,
    pub archived_size: usize,
    pub fields: Vec<(String, usize, FieldKind)>,
}

impl StructSchema {
    pub fn new(
        name: impl Into<String>,
        archived_size: usize,
        fields: Vec<(String, usize, FieldKind)>,
    ) -> Self {
        Self {
            name: name.into(),
            archived_size,
            fields,
        }
    }

    /// Renders a MoonBit source file that expects `mizchi/rkyv` as `@rkyv`.
    pub fn render_moonbit(&self) -> String {
        let view = format!("{}View", self.name);
        let mut output = String::new();

        output.push_str("///|\n");
        writeln!(output, "pub struct {view} {{").unwrap();
        output.push_str("  reader : @rkyv.Reader\n");
        output.push_str("  offset : Int\n");
        output.push_str("}\n\n");
        output.push_str("///|\n");
        writeln!(output, "pub fn {view}::at(").unwrap();
        output.push_str("  reader : @rkyv.Reader,\n");
        output.push_str("  offset : Int,\n");
        writeln!(output, ") -> Result[{view}, @rkyv.RkyvError] {{").unwrap();
        writeln!(
            output,
            "  match reader.validate_range(offset, {}) {{",
            self.archived_size
        )
        .unwrap();
        output.push_str("    Ok(_) => Ok({ reader, offset })\n");
        output.push_str("    Err(error) => Err(error)\n");
        output.push_str("  }\n");
        output.push_str("}\n\n");
        output.push_str("///|\n");
        let root_signature =
            format!("pub fn {view}::root(bytes : Bytes) -> Result[{view}, @rkyv.RkyvError] {{");
        // moonfmt keeps the 81-column ProfileView/AccountView forms on one
        // line, but wraps the 85-column DirectoryView form. Keep generated
        // fixtures formatter-stable instead of requiring a formatting pass.
        if root_signature.len() > 82 {
            writeln!(output, "pub fn {view}::root(").unwrap();
            output.push_str("  bytes : Bytes,\n");
            writeln!(output, ") -> Result[{view}, @rkyv.RkyvError] {{").unwrap();
        } else {
            writeln!(output, "{root_signature}").unwrap();
        }
        output.push_str("  let reader = @rkyv.Reader::new(bytes)\n");
        writeln!(
            output,
            "  match reader.root_offset({}) {{",
            self.archived_size
        )
        .unwrap();
        writeln!(output, "    Ok(offset) => {view}::at(reader, offset)").unwrap();
        output.push_str("    Err(error) => Err(error)\n");
        output.push_str("  }\n");
        output.push_str("}\n");

        for (name, offset, kind) in &self.fields {
            let vec_view = match kind {
                FieldKind::VecStruct(_, _) => Some(vec_view_name(&view, name)),
                _ => None,
            };
            let moonbit_type = moonbit_field_type(kind, vec_view.as_deref());
            output.push_str("\n///|\n");
            let one_line_signature = format!(
                "pub fn {view}::{name}(self : {view}) -> Result[{moonbit_type}, @rkyv.RkyvError] {{"
            );
            if matches!(kind, FieldKind::VecU32 | FieldKind::VecStruct(_, _))
                || one_line_signature.len() > 80
            {
                writeln!(output, "pub fn {view}::{name}(").unwrap();
                writeln!(output, "  self : {view},").unwrap();
                writeln!(output, ") -> Result[{moonbit_type}, @rkyv.RkyvError] {{").unwrap();
            } else {
                writeln!(output, "{one_line_signature}").unwrap();
            }
            let offset = if *offset == 0 {
                "self.offset".to_owned()
            } else {
                format!("self.offset + {offset}")
            };
            render_read(
                &mut output,
                kind,
                "self.reader",
                &offset,
                "  ",
                vec_view.as_deref(),
            );
            output.push_str("}\n");

            if let (Some(vec_view), FieldKind::VecStruct(element, element_size)) = (vec_view, kind)
            {
                render_vec_struct_view(&mut output, &vec_view, element, *element_size);
            }
        }

        output
    }
}

fn moonbit_type(kind: &FieldKind) -> String {
    match kind {
        FieldKind::U8 => "Byte".to_owned(),
        FieldKind::U16 | FieldKind::U32 => "UInt".to_owned(),
        FieldKind::U64 => "UInt64".to_owned(),
        FieldKind::I8 | FieldKind::I16 | FieldKind::I32 => "Int".to_owned(),
        FieldKind::I64 => "Int64".to_owned(),
        FieldKind::F32 => "Float".to_owned(),
        FieldKind::F64 => "Double".to_owned(),
        FieldKind::Bool => "Bool".to_owned(),
        FieldKind::String => "String".to_owned(),
        FieldKind::VecU32 => "@rkyv.U32VecView".to_owned(),
        FieldKind::VecStruct(_, _) => unreachable!("vector views need their field-specific name"),
        FieldKind::Struct(name) => format!("{name}View"),
        FieldKind::Option(inner, _) => format!("{}?", moonbit_type(inner)),
    }
}

fn moonbit_field_type(kind: &FieldKind, vec_view: Option<&str>) -> String {
    match kind {
        FieldKind::VecStruct(_, _) => vec_view
            .expect("vector fields always receive a generated view name")
            .to_owned(),
        _ => moonbit_type(kind),
    }
}

fn vec_view_name(parent_view: &str, field: &str) -> String {
    let parent = parent_view.strip_suffix("View").unwrap_or(parent_view);
    let mut field_name = String::new();
    for part in field.split('_').filter(|part| !part.is_empty()) {
        let mut chars = part.chars();
        if let Some(first) = chars.next() {
            field_name.extend(first.to_uppercase());
            field_name.push_str(chars.as_str());
        }
    }
    format!("{parent}{field_name}View")
}

fn read_expression(kind: &FieldKind, reader: &str, offset: &str) -> String {
    match kind {
        FieldKind::U8 => format!("{reader}.read_u8({offset})"),
        FieldKind::U16 => format!("{reader}.read_u16({offset})"),
        FieldKind::U32 => format!("{reader}.read_u32({offset})"),
        FieldKind::U64 => format!("{reader}.read_u64({offset})"),
        FieldKind::I8 => format!("{reader}.read_i8({offset})"),
        FieldKind::I16 => format!("{reader}.read_i16({offset})"),
        FieldKind::I32 => format!("{reader}.read_i32({offset})"),
        FieldKind::I64 => format!("{reader}.read_i64({offset})"),
        FieldKind::F32 => format!("{reader}.read_f32({offset})"),
        FieldKind::F64 => format!("{reader}.read_f64({offset})"),
        FieldKind::Bool => format!("{reader}.read_bool({offset})"),
        FieldKind::String => format!("{reader}.read_string({offset})"),
        FieldKind::VecU32 => format!("{reader}.read_vec_u32({offset})"),
        FieldKind::VecStruct(_, _) => unreachable!("vector views are rendered separately"),
        FieldKind::Struct(name) => format!("{name}View::at({reader}, {offset})"),
        FieldKind::Option(_, _) => unreachable!("nested options are rejected by the derive"),
    }
}

fn render_read(
    output: &mut String,
    kind: &FieldKind,
    reader: &str,
    offset: &str,
    indent: &str,
    vec_view: Option<&str>,
) {
    match kind {
        FieldKind::Option(inner, alignment) => {
            writeln!(
                output,
                "{indent}match {reader}.read_option_value_offset({offset}, {alignment}) {{"
            )
            .unwrap();
            writeln!(output, "{indent}  Err(error) => Err(error)").unwrap();
            writeln!(output, "{indent}  Ok(None) => Ok(None)").unwrap();
            writeln!(output, "{indent}  Ok(Some(value_offset)) =>").unwrap();
            writeln!(
                output,
                "{indent}    match {} {{",
                read_expression(inner, reader, "value_offset")
            )
            .unwrap();
            writeln!(output, "{indent}      Err(error) => Err(error)").unwrap();
            writeln!(output, "{indent}      Ok(value) => Ok(Some(value))").unwrap();
            writeln!(output, "{indent}    }}").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecStruct(_, element_size) => {
            let _ = vec_view.expect("vector fields always receive a generated view name");
            writeln!(
                output,
                "{indent}match {reader}.read_vec_header_with_element_size({offset}, {element_size}) {{"
            )
            .unwrap();
            writeln!(output, "{indent}  Err(error) => Err(error)").unwrap();
            writeln!(output, "{indent}  Ok(header) =>").unwrap();
            writeln!(output, "{indent}    Ok({{").unwrap();
            writeln!(output, "{indent}      reader: {reader},").unwrap();
            writeln!(output, "{indent}      data_offset: header.data_offset,").unwrap();
            writeln!(output, "{indent}      length: header.length,").unwrap();
            writeln!(output, "{indent}    }})").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        _ => writeln!(output, "{indent}{}", read_expression(kind, reader, offset)).unwrap(),
    }
}

fn render_vec_struct_view(output: &mut String, view: &str, element: &str, element_size: usize) {
    output.push_str("\n///|\n");
    writeln!(output, "pub struct {view} {{").unwrap();
    output.push_str("  reader : @rkyv.Reader\n");
    output.push_str("  data_offset : Int\n");
    output.push_str("  length : Int\n");
    output.push_str("}\n\n");
    output.push_str("///|\n");
    writeln!(output, "pub fn {view}::length(self : {view}) -> Int {{").unwrap();
    output.push_str("  self.length\n");
    output.push_str("}\n\n");
    output.push_str("///|\n");
    writeln!(output, "pub fn {view}::at(").unwrap();
    writeln!(output, "  self : {view},").unwrap();
    output.push_str("  index : Int,\n");
    writeln!(output, ") -> Result[{element}View?, @rkyv.RkyvError] {{").unwrap();
    output.push_str("  if index < 0 || index >= self.length {\n");
    output.push_str("    Ok(None)\n");
    output.push_str("  } else {\n");
    writeln!(
        output,
        "    match {element}View::at(self.reader, self.data_offset + index * {element_size}) {{"
    )
    .unwrap();
    output.push_str("      Err(error) => Err(error)\n");
    output.push_str("      Ok(value) => Ok(Some(value))\n");
    output.push_str("    }\n");
    output.push_str("  }\n");
    output.push_str("}\n");
}

/// Implemented by `#[derive(RkyvMbt)]` for supported Rust structs.
pub trait RkyvMbt {
    fn rkyv_mbt_schema() -> StructSchema;
}

/// Writes the binding source for a derived Rust type.
///
/// Call this from a small Rust generator binary in the same crate as the
/// `#[derive(Archive, RkyvMbt)]` type so the Rust compiler supplies the actual
/// archived layout.
pub fn write_moonbit<T: RkyvMbt>(path: impl AsRef<Path>) -> std::io::Result<()> {
    std::fs::write(path, T::rkyv_mbt_schema().render_moonbit())
}
