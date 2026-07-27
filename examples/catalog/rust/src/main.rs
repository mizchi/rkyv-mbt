use std::{
    fs, io,
    path::{Path, PathBuf},
};

use rkyv::{Archive, Serialize, access, rancor::Error, to_bytes};
use rkyv_mbt_codegen::{RkyvMbt, RkyvMbtEnum};
use rkyv_mbt_derive::RkyvMbt;

/// A product record emitted by the Rust build step and consumed by MoonBit.
#[derive(Archive, Serialize, RkyvMbt)]
pub struct Product {
    pub id: u32,
    pub price_cents: u32,
    pub stock: Option<u32>,
    pub name: String,
    pub tags: Vec<String>,
}

/// The static catalog downloaded by a client as a single rkyv archive.
#[derive(Archive, Serialize, RkyvMbt)]
pub struct Catalog {
    pub revision: u32,
    pub products: Vec<Product>,
}

/// A compile-checked generated binding that exercises the generic primitive
/// vector and `Option<Vec<T>>` paths without changing the catalog wire type.
#[derive(Archive, Serialize, RkyvMbt)]
pub struct Telemetry {
    pub samples: Vec<i16>,
    pub ratios: Vec<f64>,
    pub labels: Option<Vec<String>>,
    pub maybe_samples: Option<Vec<i16>>,
}

/// A fieldless rkyv enum generated into the MoonBit package as a strict typed
/// tag reader and writer.
#[derive(Archive, Serialize, RkyvMbt)]
pub enum CatalogState {
    Draft,
    Published,
    Retired,
}

fn sample_catalog() -> Catalog {
    Catalog {
        revision: 7,
        products: vec![
            Product {
                id: 1001,
                price_cents: 580,
                stock: Some(24),
                name: "Sea Salt".into(),
                tags: vec!["grocery".into(), "pantry".into()],
            },
            Product {
                id: 1002,
                price_cents: 1800,
                stock: Some(12),
                name: "Moon Mug".into(),
                tags: vec!["kitchen".into(), "gift".into()],
            },
            Product {
                id: 1003,
                price_cents: 2400,
                stock: None,
                name: "Orbit Tote".into(),
                tags: vec!["bag".into(), "limited".into()],
            },
        ],
    }
}

fn outputs() -> Result<Vec<(PathBuf, Vec<u8>)>, Box<dyn std::error::Error>> {
    let archive = to_bytes::<Error>(&sample_catalog())?;
    Ok(vec![
        (
            PathBuf::from("examples/catalog/generated/product.mbt"),
            Product::rkyv_mbt_schema()
                .render_moonbit_with_encoder()?
                .into_bytes(),
        ),
        (
            PathBuf::from("examples/catalog/generated/catalog.mbt"),
            Catalog::rkyv_mbt_schema()
                .render_moonbit_with_encoder()?
                .into_bytes(),
        ),
        (
            PathBuf::from("examples/catalog/generated/telemetry.mbt"),
            Telemetry::rkyv_mbt_schema()
                .render_moonbit_with_encoder()?
                .into_bytes(),
        ),
        (
            PathBuf::from("examples/catalog/generated/catalog_state.mbt"),
            CatalogState::rkyv_mbt_enum_schema()
                .render_moonbit_with_encoder()
                .into_bytes(),
        ),
        (
            PathBuf::from("examples/catalog/data/catalog.rkyv"),
            archive.to_vec(),
        ),
    ])
}

fn write_or_check(path: &Path, contents: &[u8], check: bool) -> io::Result<bool> {
    match fs::read(path) {
        Ok(current) if current == contents => Ok(false),
        _ if check => {
            eprintln!("stale generated file: {}", path.display());
            Ok(true)
        }
        _ => {
            let parent = path
                .parent()
                .expect("generated file has a parent directory");
            fs::create_dir_all(parent)?;
            fs::write(path, contents)?;
            println!("wrote {}", path.display());
            Ok(false)
        }
    }
}

fn verify_moonbit_archive(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let bytes = fs::read(path)?;
    let catalog = access::<ArchivedCatalog, Error>(&bytes)?;
    assert_eq!(catalog.revision.to_native(), 8);
    let products = catalog.products.as_slice();
    assert_eq!(products.len(), 2);

    let first = &products[0];
    assert_eq!(first.id.to_native(), 2001);
    assert_eq!(first.price_cents.to_native(), 450);
    assert_eq!(first.stock.as_ref().map(|value| value.to_native()), Some(9));
    assert_eq!(first.name.as_str(), "Moon Plate");
    assert_eq!(first.tags.as_slice()[0].as_str(), "kitchen");
    assert_eq!(first.tags.as_slice()[1].as_str(), "blue");

    let second = &products[1];
    assert_eq!(second.id.to_native(), 2002);
    assert_eq!(second.stock.as_ref().map(|value| value.to_native()), None);
    assert_eq!(second.name.as_str(), "Bag");
    assert_eq!(second.tags.as_slice()[0].as_str(), "gift");
    Ok(())
}

fn verify_moonbit_telemetry(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let bytes = fs::read(path)?;
    let telemetry = access::<ArchivedTelemetry, Error>(&bytes)?;
    assert_eq!(telemetry.samples.as_slice(), &[-7, 12, 1024]);
    assert_eq!(telemetry.ratios.as_slice(), &[1.5, -2.25]);
    assert_eq!(
        telemetry.labels.as_ref().map(|labels| labels
            .as_slice()
            .iter()
            .map(|value| value.as_str())
            .collect::<Vec<_>>()),
        Some(vec!["fast", "cold"]),
    );
    assert_eq!(
        telemetry.maybe_samples.as_ref().map(|samples| samples
            .as_slice()
            .iter()
            .map(|value| value.to_native())
            .collect::<Vec<_>>()),
        Some(vec![-1, 7]),
    );
    Ok(())
}

fn verify_moonbit_state(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let bytes = fs::read(path)?;
    let state = access::<ArchivedCatalogState, Error>(&bytes)?;
    assert!(matches!(state, ArchivedCatalogState::Published));
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let arguments = std::env::args().skip(1).collect::<Vec<_>>();
    if let [command, path] = arguments.as_slice()
        && command == "--verify-moonbit"
    {
        return verify_moonbit_archive(Path::new(path));
    }
    if let [command, path] = arguments.as_slice()
        && command == "--verify-telemetry"
    {
        return verify_moonbit_telemetry(Path::new(path));
    }
    if let [command, path] = arguments.as_slice()
        && command == "--verify-state"
    {
        return verify_moonbit_state(Path::new(path));
    }
    let check = arguments.iter().any(|argument| argument == "--check");
    let mut stale = false;
    for (path, source) in outputs()? {
        stale |= write_or_check(&path, &source, check)?;
    }
    if stale {
        return Err(io::Error::other("catalog generated files are stale").into());
    }
    Ok(())
}
