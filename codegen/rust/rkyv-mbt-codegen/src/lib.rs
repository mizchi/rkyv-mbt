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
    VecPrimitive(Box<FieldKind>, usize),
    VecString,
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

/// A Rust `#[derive(Archive)]` fieldless enum. rkyv generates these archived
/// enums as `#[repr(u8)]`, so their tag is a portable one-byte value at the
/// beginning of the root representation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EnumSchema {
    pub name: String,
    pub archived_size: usize,
    pub variants: Vec<(String, u8)>,
}

impl EnumSchema {
    pub fn new(name: impl Into<String>, archived_size: usize, variants: Vec<(String, u8)>) -> Self {
        Self {
            name: name.into(),
            archived_size,
            variants,
        }
    }

    /// Renders a strict, read-only view for a fieldless rkyv enum.
    pub fn render_moonbit(&self) -> String {
        let view = format!("{}View", self.name);
        let tag = format!("{}Tag", self.name);
        let mut output = String::new();

        output.push_str("///|\n");
        writeln!(output, "pub enum {tag} {{").unwrap();
        for (name, _) in &self.variants {
            writeln!(output, "  {name}").unwrap();
        }
        output.push_str("} derive(Debug, Eq)\n\n");

        output.push_str("///|\n");
        writeln!(output, "pub struct {view} {{").unwrap();
        output.push_str("  reader : @rkyv.Reader\n");
        output.push_str("  offset : Int\n");
        output.push_str("}\n\n");
        output.push_str("///|\n");
        writeln!(output, "pub fn {view}::at(").unwrap();
        output.push_str("  reader : @rkyv.Reader,\n");
        output.push_str("  offset : Int,\n");
        writeln!(output, ") -> {view} raise @rkyv.RkyvError {{").unwrap();
        writeln!(
            output,
            "  reader.validate_range(offset, {})",
            self.archived_size
        )
        .unwrap();
        output.push_str("  { reader, offset }\n}\n\n");
        output.push_str("///|\n");
        writeln!(
            output,
            "pub fn {view}::root(bytes : Bytes) -> {view} raise @rkyv.RkyvError {{"
        )
        .unwrap();
        output.push_str("  let reader = @rkyv.Reader::new(bytes)\n");
        writeln!(
            output,
            "  let offset = reader.root_offset({})",
            self.archived_size
        )
        .unwrap();
        writeln!(output, "  {view}::at(reader, offset)\n}}").unwrap();
        output.push_str("\n///|\n");
        writeln!(
            output,
            "pub fn {view}::validate(bytes : Bytes) -> {view} raise @rkyv.RkyvError {{"
        )
        .unwrap();
        writeln!(output, "  let view = {view}::root(bytes)").unwrap();
        output.push_str("  let _ = view.tag()\n  view\n}\n\n");
        output.push_str("///|\n");
        writeln!(
            output,
            "pub fn {view}::tag(self : {view}) -> {tag} raise @rkyv.RkyvError {{"
        )
        .unwrap();
        output.push_str("  let value = self.reader.read_union_tag(self.offset, [");
        for (index, (_, value)) in self.variants.iter().enumerate() {
            if index > 0 {
                output.push_str(", ");
            }
            write!(output, "b'\\x{value:02x}'").unwrap();
        }
        output.push_str("])\n  match value {\n");
        for (name, value) in &self.variants {
            writeln!(output, "    b'\\x{value:02x}' => {tag}::{name}").unwrap();
        }
        output.push_str("    _ => abort(\"validated enum tag was not matched\")\n  }\n}\n");
        output
    }

    /// Renders the view plus a type-safe MoonBit writer for a fieldless enum.
    pub fn render_moonbit_with_encoder(&self) -> String {
        let input = format!("{}Input", self.name);
        let mut output = self.render_moonbit();
        output.push_str("\n///|\n");
        writeln!(output, "pub(all) enum {input} {{").unwrap();
        for (name, _) in &self.variants {
            writeln!(output, "  {name}").unwrap();
        }
        output.push_str("}\n\n");
        output.push_str("///|\n");
        writeln!(output, "pub fn {input}::schema() -> @rkyv.Schema {{").unwrap();
        output.push_str("  @rkyv.Schema::TaggedUnion(\n    [\n");
        for (name, value) in &self.variants {
            writeln!(
                output,
                "      {{ name: \"{name}\", tag: b'\\x{value:02x}', schema: @rkyv.Schema::Struct([]) }},"
            )
            .unwrap();
        }
        writeln!(
            output,
            "    ],\n    0,\n    0,\n    {},\n  )\n}}",
            self.archived_size
        )
        .unwrap();
        output.push_str("\n///|\n");
        writeln!(
            output,
            "pub fn {input}::to_value(self : {input}) -> @rkyv.Value {{"
        )
        .unwrap();
        output.push_str("  match self {\n");
        for (name, value) in &self.variants {
            writeln!(
                output,
                "    {input}::{name} => @rkyv.Value::Tagged(b'\\x{value:02x}', None)"
            )
            .unwrap();
        }
        output.push_str("  }\n}\n\n");
        output.push_str("///|\n");
        writeln!(
            output,
            "pub fn {input}::encode(self : {input}) -> Bytes raise @rkyv.SchemaError {{"
        )
        .unwrap();
        writeln!(output, "  {input}::schema().encode(self.to_value())\n}}").unwrap();
        output
    }
}

/// An encoding binding cannot be emitted for a field whose MoonBit host
/// runtime representation is not yet implemented.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EncoderRenderError {
    pub struct_name: String,
    pub field_name: String,
    pub field_kind: FieldKind,
}

impl std::fmt::Display for EncoderRenderError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "cannot generate MoonBit encoder for {}.{} ({:?})",
            self.struct_name, self.field_name, self.field_kind
        )
    }
}

impl std::error::Error for EncoderRenderError {}

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
        writeln!(output, ") -> {view} raise @rkyv.RkyvError {{").unwrap();
        writeln!(
            output,
            "  reader.validate_range(offset, {})",
            self.archived_size
        )
        .unwrap();
        output.push_str("  { reader, offset }\n");
        output.push_str("}\n\n");
        output.push_str("///|\n");
        let root_signature =
            format!("pub fn {view}::root(bytes : Bytes) -> {view} raise @rkyv.RkyvError {{");
        // moonfmt keeps the shorter ProfileView/AccountView forms on one line,
        // but wraps the 82-column DirectoryView form. Keep generated
        // fixtures formatter-stable instead of requiring a formatting pass.
        if root_signature.len() >= 82 {
            writeln!(output, "pub fn {view}::root(").unwrap();
            output.push_str("  bytes : Bytes,\n");
            writeln!(output, ") -> {view} raise @rkyv.RkyvError {{").unwrap();
        } else {
            writeln!(output, "{root_signature}").unwrap();
        }
        output.push_str("  let reader = @rkyv.Reader::new(bytes)\n");
        writeln!(
            output,
            "  let offset = reader.root_offset({})",
            self.archived_size
        )
        .unwrap();
        writeln!(output, "  {view}::at(reader, offset)").unwrap();
        output.push_str("}\n");

        output.push_str("\n///|\n");
        let validate_signature =
            format!("pub fn {view}::validate(bytes : Bytes) -> {view} raise @rkyv.RkyvError {{");
        if validate_signature.len() >= 82 {
            writeln!(output, "pub fn {view}::validate(").unwrap();
            output.push_str("  bytes : Bytes,\n");
            writeln!(output, ") -> {view} raise @rkyv.RkyvError {{").unwrap();
        } else {
            writeln!(output, "{validate_signature}").unwrap();
        }
        writeln!(output, "  let view = {view}::root(bytes)").unwrap();
        output.push_str("  view.validate_all(256)\n");
        output.push_str("  view\n");
        output.push_str("}\n");

        output.push_str("\n///|\n");
        writeln!(output, "pub fn {view}::validate_all(").unwrap();
        writeln!(output, "  self : {view},").unwrap();
        output.push_str("  remaining_depth : Int,\n");
        output.push_str(") -> Unit raise @rkyv.RkyvError {\n");
        output.push_str("  @rkyv.require_validation_depth(remaining_depth)\n");
        for (name, offset, kind) in &self.fields {
            let offset = if *offset == 0 {
                "self.offset".to_owned()
            } else {
                format!("self.offset + {offset}")
            };
            render_validation(
                &mut output,
                kind,
                "self.reader",
                &offset,
                &format!("self.{name}()"),
                "  ",
            );
        }
        output.push_str("}\n");

        for (name, offset, kind) in &self.fields {
            let vec_view = vector_kind(kind).map(|_| vec_view_name(&view, name));
            let moonbit_type = moonbit_field_type(kind, vec_view.as_deref());
            output.push_str("\n///|\n");
            let one_line_signature = format!(
                "pub fn {view}::{name}(self : {view}) -> {moonbit_type} raise @rkyv.RkyvError {{"
            );
            if matches!(
                kind,
                FieldKind::VecU32
                    | FieldKind::VecPrimitive(_, _)
                    | FieldKind::VecString
                    | FieldKind::VecStruct(_, _)
            ) || one_line_signature.len() > 80
            {
                writeln!(output, "pub fn {view}::{name}(").unwrap();
                writeln!(output, "  self : {view},").unwrap();
                writeln!(output, ") -> {moonbit_type} raise @rkyv.RkyvError {{").unwrap();
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

            if let Some(vec_view) = vec_view {
                match vector_kind(kind).expect("field-specific vector view") {
                    FieldKind::VecPrimitive(element, element_size) => {
                        render_vec_primitive_view(&mut output, &vec_view, element, *element_size)
                    }
                    FieldKind::VecString => render_vec_string_view(&mut output, &vec_view),
                    FieldKind::VecStruct(element, element_size) => {
                        render_vec_struct_view(&mut output, &vec_view, element, *element_size)
                    }
                    _ => unreachable!("only field-specific vectors create a vector view"),
                }
            }
        }

        output
    }

    /// Renders the lazy read view plus a typed MoonBit input/encoder API.
    ///
    /// Linked struct fields require the referenced bindings to be rendered
    /// with this method as well, so their `*Input` type is available.
    pub fn render_moonbit_with_encoder(&self) -> Result<String, EncoderRenderError> {
        for (field_name, _, field_kind) in &self.fields {
            if !encoder_supported(field_kind) {
                return Err(EncoderRenderError {
                    struct_name: self.name.clone(),
                    field_name: field_name.clone(),
                    field_kind: field_kind.clone(),
                });
            }
        }

        let mut output = self.render_moonbit();
        render_encoder(&mut output, self);
        Ok(output)
    }
}

fn encoder_supported(_kind: &FieldKind) -> bool {
    true
}

fn input_name(name: &str) -> String {
    format!("{name}Input")
}

fn encoder_input_type(kind: &FieldKind) -> String {
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
        FieldKind::VecU32 => "Array[UInt]".to_owned(),
        FieldKind::VecPrimitive(element, _) => format!("Array[{}]", moonbit_type(element)),
        FieldKind::VecString => "Array[String]".to_owned(),
        FieldKind::VecStruct(name, _) => format!("Array[{}]", input_name(name)),
        FieldKind::Struct(name) => input_name(name),
        FieldKind::Option(inner, _) => format!("{}?", encoder_input_type(inner)),
    }
}

fn encoder_schema_expression(kind: &FieldKind) -> String {
    match kind {
        FieldKind::U8 => "@rkyv.Schema::U8".to_owned(),
        FieldKind::U16 => "@rkyv.Schema::U16".to_owned(),
        FieldKind::U32 => "@rkyv.Schema::U32".to_owned(),
        FieldKind::U64 => "@rkyv.Schema::U64".to_owned(),
        FieldKind::I8 => "@rkyv.Schema::I8".to_owned(),
        FieldKind::I16 => "@rkyv.Schema::I16".to_owned(),
        FieldKind::I32 => "@rkyv.Schema::I32".to_owned(),
        FieldKind::I64 => "@rkyv.Schema::I64".to_owned(),
        FieldKind::F32 => "@rkyv.Schema::F32".to_owned(),
        FieldKind::F64 => "@rkyv.Schema::F64".to_owned(),
        FieldKind::Bool => "@rkyv.Schema::Bool".to_owned(),
        FieldKind::String => "@rkyv.Schema::String".to_owned(),
        FieldKind::VecU32 => "@rkyv.Schema::VecU32".to_owned(),
        FieldKind::VecPrimitive(element, _) => {
            format!("@rkyv.Schema::Vec({})", encoder_schema_expression(element))
        }
        FieldKind::VecString => "@rkyv.Schema::Vec(@rkyv.Schema::String)".to_owned(),
        FieldKind::VecStruct(name, _) => {
            format!("@rkyv.Schema::Vec({}::schema())", input_name(name))
        }
        FieldKind::Struct(name) => format!("{}::schema()", input_name(name)),
        FieldKind::Option(inner, _) => {
            format!("@rkyv.Schema::Option({})", encoder_schema_expression(inner))
        }
    }
}

fn encoder_scalar_value_expression(kind: &FieldKind, value: &str) -> String {
    match kind {
        FieldKind::U8 => format!("@rkyv.Value::U8({value})"),
        FieldKind::U16 => format!("@rkyv.Value::U16({value})"),
        FieldKind::U32 => format!("@rkyv.Value::U32({value})"),
        FieldKind::U64 => format!("@rkyv.Value::U64({value})"),
        FieldKind::I8 => format!("@rkyv.Value::I8({value})"),
        FieldKind::I16 => format!("@rkyv.Value::I16({value})"),
        FieldKind::I32 => format!("@rkyv.Value::I32({value})"),
        FieldKind::I64 => format!("@rkyv.Value::I64({value})"),
        FieldKind::F32 => format!("@rkyv.Value::F32({value})"),
        FieldKind::F64 => format!("@rkyv.Value::F64({value})"),
        FieldKind::Bool => format!("@rkyv.Value::Bool({value})"),
        FieldKind::String => format!("@rkyv.Value::String({value})"),
        FieldKind::Struct(_) => format!("{value}.to_value()"),
        _ => unreachable!("only scalar encoder values use this helper"),
    }
}

fn render_encoder(output: &mut String, schema: &StructSchema) {
    let input = input_name(&schema.name);
    output.push_str("\n///|\n");
    writeln!(output, "pub struct {input} {{").unwrap();
    for (field_name, _, field_kind) in &schema.fields {
        writeln!(
            output,
            "  {field_name} : {}",
            encoder_input_type(field_kind)
        )
        .unwrap();
    }
    output.push_str("}\n\n");

    output.push_str("///|\n");
    writeln!(output, "pub fn {input}::new(").unwrap();
    for (field_name, _, field_kind) in &schema.fields {
        writeln!(
            output,
            "  {field_name} : {},",
            encoder_input_type(field_kind)
        )
        .unwrap();
    }
    writeln!(output, ") -> {input} {{").unwrap();
    output.push_str("  { ");
    for (index, (field_name, _, _)) in schema.fields.iter().enumerate() {
        if index > 0 {
            output.push_str(", ");
        }
        output.push_str(field_name);
    }
    output.push_str(" }\n}\n\n");

    let mut layout_fields = schema.fields.clone();
    layout_fields.sort_by_key(|(_, offset, _)| *offset);
    output.push_str("///|\n");
    writeln!(output, "pub fn {input}::schema() -> @rkyv.Schema {{").unwrap();
    output.push_str("  @rkyv.Schema::StructLayout(\n");
    output.push_str("    [\n");
    for (field_name, _, field_kind) in &layout_fields {
        writeln!(
            output,
            "      {{ name: \"{field_name}\", schema: {} }},",
            encoder_schema_expression(field_kind)
        )
        .unwrap();
    }
    output.push_str("    ],\n");
    output.push_str("    [");
    for (index, (_, offset, _)) in layout_fields.iter().enumerate() {
        if index > 0 {
            output.push_str(", ");
        }
        write!(output, "{offset}").unwrap();
    }
    output.push_str("],\n");
    writeln!(output, "    {},", schema.archived_size).unwrap();
    output.push_str("  )\n}\n\n");

    output.push_str("///|\n");
    writeln!(
        output,
        "pub fn {input}::to_value(self : {input}) -> @rkyv.Value {{"
    )
    .unwrap();
    for (field_name, _, field_kind) in &layout_fields {
        render_encoder_value_binding(
            output,
            field_kind,
            &format!("self.{field_name}"),
            &format!("{field_name}_value"),
            "  ",
        );
    }
    output.push_str("  @rkyv.Value::Struct([\n");
    for (field_name, _, _) in &layout_fields {
        writeln!(
            output,
            "    {{ name: \"{field_name}\", value: {field_name}_value }},"
        )
        .unwrap();
    }
    output.push_str("  ])\n}\n\n");

    output.push_str("///|\n");
    let encode_signature =
        format!("pub fn {input}::encode(self : {input}) -> Bytes raise @rkyv.SchemaError {{");
    if encode_signature.len() >= 82 {
        writeln!(output, "pub fn {input}::encode(").unwrap();
        writeln!(output, "  self : {input},").unwrap();
        output.push_str(") -> Bytes raise @rkyv.SchemaError {\n");
    } else {
        writeln!(output, "{encode_signature}").unwrap();
    }
    writeln!(output, "  {input}::schema().encode(self.to_value())").unwrap();
    output.push_str("}\n");
}

fn render_encoder_value_binding(
    output: &mut String,
    kind: &FieldKind,
    source: &str,
    target: &str,
    indent: &str,
) {
    match kind {
        FieldKind::VecU32 => {
            writeln!(
                output,
                "{indent}let {target} = @rkyv.Value::VecU32({source})"
            )
            .unwrap();
        }
        FieldKind::VecPrimitive(element, _) => {
            let values = format!("{target}_items");
            writeln!(output, "{indent}let {values} : Array[@rkyv.Value] = []").unwrap();
            writeln!(output, "{indent}for value in {source} {{").unwrap();
            writeln!(
                output,
                "{indent}  {values}.push({})",
                encoder_scalar_value_expression(element, "value")
            )
            .unwrap();
            writeln!(output, "{indent}}}").unwrap();
            writeln!(output, "{indent}let {target} = @rkyv.Value::Vec({values})").unwrap();
        }
        FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            let values = format!("{target}_items");
            writeln!(output, "{indent}let {values} : Array[@rkyv.Value] = []").unwrap();
            writeln!(output, "{indent}for value in {source} {{").unwrap();
            let value_expression = match kind {
                FieldKind::VecString => "@rkyv.Value::String(value)".to_owned(),
                FieldKind::VecStruct(_, _) => "value.to_value()".to_owned(),
                _ => unreachable!(),
            };
            writeln!(output, "{indent}  {values}.push({value_expression})").unwrap();
            writeln!(output, "{indent}}}").unwrap();
            writeln!(output, "{indent}let {target} = @rkyv.Value::Vec({values})").unwrap();
        }
        FieldKind::Option(inner, _) => {
            writeln!(output, "{indent}let {target} = match {source} {{").unwrap();
            writeln!(output, "{indent}  None => @rkyv.Value::Option(None)").unwrap();
            writeln!(output, "{indent}  Some(value) => {{").unwrap();
            let some_target = format!("{target}_some");
            render_encoder_value_binding(
                output,
                inner,
                "value",
                &some_target,
                &format!("{indent}    "),
            );
            writeln!(
                output,
                "{indent}    @rkyv.Value::Option(Some({some_target}))"
            )
            .unwrap();
            writeln!(output, "{indent}  }}").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        _ => {
            writeln!(
                output,
                "{indent}let {target} = {}",
                encoder_scalar_value_expression(kind, source)
            )
            .unwrap();
        }
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
        FieldKind::VecPrimitive(_, _) | FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            unreachable!("vector views need their field-specific name")
        }
        FieldKind::Struct(name) => format!("{name}View"),
        FieldKind::Option(inner, _) => format!("{}?", moonbit_type(inner)),
    }
}

fn moonbit_field_type(kind: &FieldKind, vec_view: Option<&str>) -> String {
    match kind {
        FieldKind::VecPrimitive(_, _) | FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            vec_view
                .expect("vector fields always receive a generated view name")
                .to_owned()
        }
        FieldKind::Option(inner, _) => format!("{}?", moonbit_field_type(inner, vec_view)),
        _ => moonbit_type(kind),
    }
}

fn vector_kind(kind: &FieldKind) -> Option<&FieldKind> {
    match kind {
        FieldKind::VecPrimitive(_, _) | FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            Some(kind)
        }
        FieldKind::Option(inner, _) => vector_kind(inner),
        _ => None,
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
        FieldKind::VecPrimitive(_, _) | FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            unreachable!("vector views are rendered separately")
        }
        FieldKind::Struct(name) => format!("{name}View::at({reader}, {offset})"),
        FieldKind::Option(_, _) => unreachable!("options are rendered separately"),
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
            writeln!(output, "{indent}  None => None").unwrap();
            match vector_kind(inner) {
                Some(vector) => {
                    writeln!(output, "{indent}  Some(value_offset) => {{").unwrap();
                    render_vector_header(
                        output,
                        vector,
                        reader,
                        "value_offset",
                        &format!("{indent}    "),
                    );
                    writeln!(output, "{indent}    Some({{").unwrap();
                    writeln!(output, "{indent}      reader: {reader},").unwrap();
                    writeln!(output, "{indent}      data_offset: header.data_offset,").unwrap();
                    writeln!(output, "{indent}      length: header.length,").unwrap();
                    writeln!(output, "{indent}    }})").unwrap();
                    writeln!(output, "{indent}  }}").unwrap();
                }
                None => {
                    writeln!(
                        output,
                        "{indent}  Some(value_offset) => Some({})",
                        read_expression(inner, reader, "value_offset")
                    )
                    .unwrap();
                }
            }
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecPrimitive(_, _) | FieldKind::VecString | FieldKind::VecStruct(_, _) => {
            let _ = vec_view.expect("vector fields always receive a generated view name");
            render_vector_header(output, kind, reader, offset, indent);
            writeln!(output, "{indent}{{").unwrap();
            writeln!(output, "{indent}  reader: {reader},").unwrap();
            writeln!(output, "{indent}  data_offset: header.data_offset,").unwrap();
            writeln!(output, "{indent}  length: header.length,").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        _ => writeln!(output, "{indent}{}", read_expression(kind, reader, offset)).unwrap(),
    }
}

fn vector_element_size(kind: &FieldKind) -> usize {
    match kind {
        FieldKind::VecPrimitive(_, element_size) | FieldKind::VecStruct(_, element_size) => {
            *element_size
        }
        FieldKind::VecString => 8,
        _ => unreachable!("only field-specific vectors have an element size"),
    }
}

fn render_vector_header(
    output: &mut String,
    kind: &FieldKind,
    reader: &str,
    offset: &str,
    indent: &str,
) {
    let element_size = vector_element_size(kind);
    let header = format!(
        "{indent}let header = {reader}.read_vec_header_with_element_size({offset}, {element_size})"
    );
    if header.len() > 80 {
        writeln!(
            output,
            "{indent}let header = {reader}.read_vec_header_with_element_size("
        )
        .unwrap();
        writeln!(output, "{indent}  {offset},").unwrap();
        writeln!(output, "{indent}  {element_size},").unwrap();
        writeln!(output, "{indent})").unwrap();
    } else {
        writeln!(output, "{header}").unwrap();
    }
}

fn render_validation(
    output: &mut String,
    kind: &FieldKind,
    reader: &str,
    offset: &str,
    accessor: &str,
    indent: &str,
) {
    match kind {
        FieldKind::Bool => {
            writeln!(
                output,
                "{indent}let _ = {reader}.read_bool_strict({offset})"
            )
            .unwrap();
        }
        FieldKind::Option(inner, alignment) => {
            writeln!(
                output,
                "{indent}match {reader}.read_option_value_offset_strict({offset}, {alignment}) {{"
            )
            .unwrap();
            writeln!(output, "{indent}  None => ()").unwrap();
            writeln!(output, "{indent}  Some(value_offset) => {{").unwrap();
            render_validation_at(
                output,
                inner,
                reader,
                "value_offset",
                &format!("{indent}    "),
            );
            writeln!(output, "{indent}  }}").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecString => {
            writeln!(output, "{indent}let values = {accessor}").unwrap();
            writeln!(output, "{indent}for index in 0..<values.length() {{").unwrap();
            writeln!(output, "{indent}  let _ = values.at(index)").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecStruct(_, _) => {
            writeln!(output, "{indent}let values = {accessor}").unwrap();
            writeln!(output, "{indent}for index in 0..<values.length() {{").unwrap();
            writeln!(output, "{indent}  match values.at(index) {{").unwrap();
            writeln!(output, "{indent}    None => ()").unwrap();
            writeln!(
                output,
                "{indent}    Some(value) => value.validate_all(remaining_depth - 1)"
            )
            .unwrap();
            writeln!(output, "{indent}  }}").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecPrimitive(_, _) => render_validation_at(output, kind, reader, offset, indent),
        _ => render_validation_at(output, kind, reader, offset, indent),
    }
}

fn render_validation_at(
    output: &mut String,
    kind: &FieldKind,
    reader: &str,
    offset: &str,
    indent: &str,
) {
    match kind {
        FieldKind::Bool => {
            writeln!(
                output,
                "{indent}let _ = {reader}.read_bool_strict({offset})"
            )
            .unwrap();
        }
        FieldKind::Struct(name) => {
            writeln!(
                output,
                "{indent}let value = {name}View::at({reader}, {offset})"
            )
            .unwrap();
            writeln!(output, "{indent}value.validate_all(remaining_depth - 1)").unwrap();
        }
        FieldKind::VecU32 => {
            writeln!(output, "{indent}let _ = {reader}.read_vec_u32({offset})").unwrap();
        }
        FieldKind::VecPrimitive(element, element_size) => {
            writeln!(
                output,
                "{indent}let header = {reader}.read_vec_header_with_element_size({offset}, {element_size})"
            )
            .unwrap();
            writeln!(output, "{indent}for index in 0..<header.length {{").unwrap();
            render_validation_at(
                output,
                element,
                reader,
                &format!("header.data_offset + index * {element_size}"),
                &format!("{indent}  "),
            );
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecString => {
            writeln!(
                output,
                "{indent}let header = {reader}.read_vec_header_with_element_size({offset}, 8)"
            )
            .unwrap();
            writeln!(output, "{indent}for index in 0..<header.length {{").unwrap();
            writeln!(
                output,
                "{indent}  let _ = {reader}.read_string(header.data_offset + index * 8)"
            )
            .unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::VecStruct(name, element_size) => {
            writeln!(
                output,
                "{indent}let header = {reader}.read_vec_header_with_element_size({offset}, {element_size})"
            )
            .unwrap();
            writeln!(output, "{indent}for index in 0..<header.length {{").unwrap();
            writeln!(
                output,
                "{indent}  let value = {name}View::at({reader}, header.data_offset + index * {element_size})"
            )
            .unwrap();
            writeln!(output, "{indent}  value.validate_all(remaining_depth - 1)").unwrap();
            writeln!(output, "{indent}}}").unwrap();
        }
        FieldKind::String
        | FieldKind::U8
        | FieldKind::U16
        | FieldKind::U32
        | FieldKind::U64
        | FieldKind::I8
        | FieldKind::I16
        | FieldKind::I32
        | FieldKind::I64
        | FieldKind::F32
        | FieldKind::F64 => {
            writeln!(
                output,
                "{indent}let _ = {}",
                read_expression(kind, reader, offset)
            )
            .unwrap();
        }
        FieldKind::Option(_, _) => unreachable!("nested options are rejected by the derive"),
    }
}

fn render_vec_primitive_view(
    output: &mut String,
    view: &str,
    element: &FieldKind,
    element_size: usize,
) {
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
    writeln!(
        output,
        ") -> {}? raise @rkyv.RkyvError {{",
        moonbit_type(element)
    )
    .unwrap();
    output.push_str("  if index < 0 || index >= self.length {\n");
    output.push_str("    None\n");
    output.push_str("  } else {\n");
    writeln!(
        output,
        "    Some({})",
        read_expression(
            element,
            "self.reader",
            &format!("self.data_offset + index * {element_size}"),
        )
    )
    .unwrap();
    output.push_str("  }\n");
    output.push_str("}\n");
}

fn render_vec_string_view(output: &mut String, view: &str) {
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
    writeln!(output, ") -> String? raise @rkyv.RkyvError {{").unwrap();
    output.push_str("  if index < 0 || index >= self.length {\n");
    output.push_str("    None\n");
    output.push_str("  } else {\n");
    output.push_str("    Some(self.reader.read_string(self.data_offset + index * 8))\n");
    output.push_str("  }\n");
    output.push_str("}\n");
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
    writeln!(output, ") -> {element}View? raise @rkyv.RkyvError {{").unwrap();
    output.push_str("  if index < 0 || index >= self.length {\n");
    output.push_str("    None\n");
    output.push_str("  } else {\n");
    writeln!(
        output,
        "    Some({element}View::at(self.reader, self.data_offset + index * {element_size}))"
    )
    .unwrap();
    output.push_str("  }\n");
    output.push_str("}\n");
}

/// Implemented by `#[derive(RkyvMbt)]` for supported Rust structs.
pub trait RkyvMbt {
    fn rkyv_mbt_schema() -> StructSchema;
}

/// Implemented by `#[derive(RkyvMbt)]` for supported fieldless Rust enums.
/// Payload enums use the explicit `Schema::TaggedUnion` contract for now,
/// because Rust does not expose stable offsets for individual enum payloads.
pub trait RkyvMbtEnum {
    fn rkyv_mbt_enum_schema() -> EnumSchema;
}

/// Writes the binding source for a derived Rust type.
///
/// Call this from a small Rust generator binary in the same crate as the
/// `#[derive(Archive, RkyvMbt)]` type so the Rust compiler supplies the actual
/// archived layout.
pub fn write_moonbit<T: RkyvMbt>(path: impl AsRef<Path>) -> std::io::Result<()> {
    std::fs::write(path, T::rkyv_mbt_schema().render_moonbit())
}

/// Writes a MoonBit binding source file for a fieldless rkyv enum.
pub fn write_moonbit_enum<T: RkyvMbtEnum>(path: impl AsRef<Path>) -> std::io::Result<()> {
    std::fs::write(path, T::rkyv_mbt_enum_schema().render_moonbit())
}
