use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::{format_ident, quote};
use syn::{
    Data, DeriveInput, Error, Expr, Fields, GenericArgument, Lit, PathArguments, Type,
    parse_macro_input,
};

#[proc_macro_derive(RkyvMbt)]
pub fn derive_rkyv_mbt(input: TokenStream) -> TokenStream {
    match derive_rkyv_mbt_impl(parse_macro_input!(input as DeriveInput)) {
        Ok(output) => output.into(),
        Err(error) => error.into_compile_error().into(),
    }
}

fn derive_rkyv_mbt_impl(input: DeriveInput) -> Result<TokenStream2, Error> {
    let name = input.ident;
    let archived_name = format_ident!("Archived{name}");
    let fields = match input.data {
        Data::Struct(structure) => match structure.fields {
            Fields::Named(fields) => fields.named,
            _ => {
                return Err(Error::new_spanned(
                    name,
                    "RkyvMbt currently supports named structs only",
                ));
            }
        },
        Data::Enum(enumeration) => return derive_fieldless_enum(name, archived_name, enumeration),
        _ => {
            return Err(Error::new_spanned(
                name,
                "RkyvMbt supports structs and fieldless enums",
            ));
        }
    };

    let fields = fields
        .iter()
        .map(|field| {
            let field_name = field.ident.as_ref().expect("named field");
            let field_name_string = field_name.to_string();
            let kind = field_kind_tokens(field_kind(&field.ty)?);
            Ok(quote! {
                (
                    #field_name_string.to_owned(),
                    ::core::mem::offset_of!(#archived_name, #field_name),
                    #kind,
                )
            })
        })
        .collect::<Result<Vec<_>, Error>>()?;

    Ok(quote! {
        impl ::rkyv_mbt_codegen::RkyvMbt for #name {
            fn rkyv_mbt_schema() -> ::rkyv_mbt_codegen::StructSchema {
                ::rkyv_mbt_codegen::StructSchema::new(
                    stringify!(#name),
                    ::core::mem::size_of::<#archived_name>(),
                    vec![#(#fields),*],
                )
            }
        }
    })
}

fn derive_fieldless_enum(
    name: syn::Ident,
    archived_name: syn::Ident,
    enumeration: syn::DataEnum,
) -> Result<TokenStream2, Error> {
    let mut next_tag = 0_u16;
    let variants = enumeration
        .variants
        .iter()
        .map(|variant| {
            if !matches!(variant.fields, Fields::Unit) {
                return Err(Error::new_spanned(
                    variant,
                    "RkyvMbt derives fieldless enums only; model payload enums with Schema::TaggedUnion so their Rust payload offset is explicit",
                ));
            }
            let tag = match &variant.discriminant {
                None => u8::try_from(next_tag).map_err(|_| {
                    Error::new_spanned(variant, "RkyvMbt enums can have at most 256 variants")
                })?,
                Some((_, Expr::Lit(expression))) => match &expression.lit {
                    Lit::Int(value) => value.base10_parse::<u8>().map_err(|_| {
                        Error::new_spanned(
                            value,
                            "RkyvMbt enum discriminants must be integer literals in 0..=255",
                        )
                    })?,
                    _ => {
                        return Err(Error::new_spanned(
                            &expression.lit,
                            "RkyvMbt enum discriminants must be integer literals in 0..=255",
                        ));
                    }
                },
                Some((_, expression)) => {
                    return Err(Error::new_spanned(
                        expression,
                        "RkyvMbt enum discriminants must be integer literals in 0..=255",
                    ));
                }
            };
            next_tag = tag as u16 + 1;
            let variant_name = variant.ident.to_string();
            Ok(quote!((#variant_name.to_owned(), #tag)))
        })
        .collect::<Result<Vec<_>, Error>>()?;

    Ok(quote! {
        impl ::rkyv_mbt_codegen::RkyvMbtEnum for #name {
            fn rkyv_mbt_enum_schema() -> ::rkyv_mbt_codegen::EnumSchema {
                ::rkyv_mbt_codegen::EnumSchema::new(
                    stringify!(#name),
                    ::core::mem::size_of::<#archived_name>(),
                    vec![#(#variants),*],
                )
            }
        }
    })
}

enum SupportedField {
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
    VecPrimitive(Box<SupportedField>, Type),
    VecString,
    VecStruct(String, Type),
    Struct(String),
    Option(Box<SupportedField>, Type),
}

fn field_kind_tokens(kind: SupportedField) -> TokenStream2 {
    match kind {
        SupportedField::U8 => quote!(::rkyv_mbt_codegen::FieldKind::U8),
        SupportedField::U16 => quote!(::rkyv_mbt_codegen::FieldKind::U16),
        SupportedField::U32 => quote!(::rkyv_mbt_codegen::FieldKind::U32),
        SupportedField::U64 => quote!(::rkyv_mbt_codegen::FieldKind::U64),
        SupportedField::I8 => quote!(::rkyv_mbt_codegen::FieldKind::I8),
        SupportedField::I16 => quote!(::rkyv_mbt_codegen::FieldKind::I16),
        SupportedField::I32 => quote!(::rkyv_mbt_codegen::FieldKind::I32),
        SupportedField::I64 => quote!(::rkyv_mbt_codegen::FieldKind::I64),
        SupportedField::F32 => quote!(::rkyv_mbt_codegen::FieldKind::F32),
        SupportedField::F64 => quote!(::rkyv_mbt_codegen::FieldKind::F64),
        SupportedField::Bool => quote!(::rkyv_mbt_codegen::FieldKind::Bool),
        SupportedField::String => quote!(::rkyv_mbt_codegen::FieldKind::String),
        SupportedField::VecU32 => quote!(::rkyv_mbt_codegen::FieldKind::VecU32),
        SupportedField::VecPrimitive(element, original_type) => {
            let element = field_kind_tokens(*element);
            quote!(::rkyv_mbt_codegen::FieldKind::VecPrimitive(
                ::std::boxed::Box::new(#element),
                ::core::mem::size_of::<<#original_type as ::rkyv::Archive>::Archived>(),
            ))
        }
        SupportedField::VecString => quote!(::rkyv_mbt_codegen::FieldKind::VecString),
        SupportedField::VecStruct(name, original_type) => {
            quote!(::rkyv_mbt_codegen::FieldKind::VecStruct(
                #name.to_owned(),
                ::core::mem::size_of::<<#original_type as ::rkyv::Archive>::Archived>(),
            ))
        }
        SupportedField::Struct(name) => {
            quote!(::rkyv_mbt_codegen::FieldKind::Struct(#name.to_owned()))
        }
        SupportedField::Option(inner, original_type) => {
            let inner = field_kind_tokens(*inner);
            quote!(::rkyv_mbt_codegen::FieldKind::Option(
                ::std::boxed::Box::new(#inner),
                ::core::mem::align_of::<<#original_type as ::rkyv::Archive>::Archived>(),
            ))
        }
    }
}

fn field_kind(ty: &Type) -> Result<SupportedField, Error> {
    let Type::Path(path) = ty else {
        return Err(Error::new_spanned(
            ty,
            "unsupported RkyvMbt field type; expected a numeric primitive, bool, String, or Vec<u32>",
        ));
    };
    let Some(segment) = path.path.segments.last() else {
        return Err(Error::new_spanned(ty, "unsupported RkyvMbt field type"));
    };

    match segment.ident.to_string().as_str() {
        "u8" => Ok(SupportedField::U8),
        "u16" => Ok(SupportedField::U16),
        "u32" => Ok(SupportedField::U32),
        "u64" => Ok(SupportedField::U64),
        "i8" => Ok(SupportedField::I8),
        "i16" => Ok(SupportedField::I16),
        "i32" => Ok(SupportedField::I32),
        "i64" => Ok(SupportedField::I64),
        "f32" => Ok(SupportedField::F32),
        "f64" => Ok(SupportedField::F64),
        "bool" => Ok(SupportedField::Bool),
        "String" => Ok(SupportedField::String),
        "Option" => match &segment.arguments {
            PathArguments::AngleBracketed(arguments)
                if arguments.args.len() == 1
                    && matches!(arguments.args.first(), Some(GenericArgument::Type(_))) =>
            {
                let Some(GenericArgument::Type(inner)) = arguments.args.first() else {
                    unreachable!("the match above establishes an inner type")
                };
                let inner_kind = field_kind(inner)?;
                if matches!(inner_kind, SupportedField::Option(_, _)) {
                    return Err(Error::new_spanned(
                        ty,
                        "RkyvMbt does not support nested Option values yet",
                    ));
                }
                Ok(SupportedField::Option(Box::new(inner_kind), inner.clone()))
            }
            _ => Err(Error::new_spanned(
                ty,
                "RkyvMbt expects Option<T> with one supported value type",
            )),
        },
        "Vec" => match &segment.arguments {
            PathArguments::AngleBracketed(arguments)
                if arguments.args.len() == 1
                    && matches!(arguments.args.first(), Some(GenericArgument::Type(Type::Path(path))) if path.path.is_ident("u32")) =>
            {
                Ok(SupportedField::VecU32)
            }
            PathArguments::AngleBracketed(arguments)
                if arguments.args.len() == 1
                    && matches!(arguments.args.first(), Some(GenericArgument::Type(Type::Path(path))) if path.path.is_ident("String")) =>
            {
                Ok(SupportedField::VecString)
            }
            PathArguments::AngleBracketed(arguments)
                if arguments.args.len() == 1
                    && matches!(arguments.args.first(), Some(GenericArgument::Type(_))) =>
            {
                let Some(GenericArgument::Type(inner)) = arguments.args.first() else {
                    unreachable!("the match above establishes an inner type")
                };
                match field_kind(inner)? {
                    SupportedField::U8
                    | SupportedField::U16
                    | SupportedField::U32
                    | SupportedField::U64
                    | SupportedField::I8
                    | SupportedField::I16
                    | SupportedField::I32
                    | SupportedField::I64
                    | SupportedField::F32
                    | SupportedField::F64
                    | SupportedField::Bool => Ok(SupportedField::VecPrimitive(
                        Box::new(field_kind(inner)?),
                        inner.clone(),
                    )),
                    SupportedField::Struct(name) => {
                        Ok(SupportedField::VecStruct(name, inner.clone()))
                    }
                    _ => Err(Error::new_spanned(
                        ty,
                        "RkyvMbt supports Vec<primitive>, Vec<String>, or Vec<named struct>",
                    )),
                }
            }
            _ => Err(Error::new_spanned(
                ty,
                "RkyvMbt supports Vec<primitive>, Vec<String>, or Vec<named struct>",
            )),
        },
        _ if matches!(segment.arguments, PathArguments::None) => {
            Ok(SupportedField::Struct(segment.ident.to_string()))
        }
        _ => Err(Error::new_spanned(
            ty,
            "unsupported RkyvMbt field type; expected a primitive, bool, String, Option<T>, Vec<T>, or a named struct",
        )),
    }
}
