# mizchi/rkyv

[English](README.md)

rkyv 0.8 の archive を MoonBit から安全に読む小さな runtime と encoder です。Rust が生成した
archive をコピーせずに参照し、schema 固有の処理は生成済み binding または application 側へ分離します。

設計は [cometkim/rkyv-js](https://github.com/cometkim/rkyv-js) と同様に、共有 wire-format runtime と
Rust 型から生成する binding に分けています。

## リリース時の保証範囲

保証する wire format は rkyv **0.8.17** のデフォルト形式です。

- little-endian
- aligned archive
- 32-bit relative pointer と archived `usize`

実行可能な互換性契約は checked reader の primitive、host-defined の scalar / vector / option /
tagged union schema、および generated catalog binding を対象にします。fixture と制約は
[conformance/README.md](conformance/README.md) を参照してください。

## 機能

- デフォルト rkyv format の bounds-checked Reader
- `u8`〜`u64`、`i8`〜`i64`、`f32`、`f64`、`bool` の bit-compatible な読み取り
- relative pointer、`ArchivedVec<T>` header、`ArchivedOption<T>` value offset
- archive の任意範囲をコピーせず借用する bounds-checked `BytesView`
- `ArchivedVec<u32>` の zero-copy lazy view、`Array` / `FixedArray` への materialize、再利用 buffer への copy
- primitive、String、vector、option、struct、明示的 tagged union を書ける default format の schema encoder
- little-endian / big-endian と pointer width 16 / 32 / 64 の primitive reader
- named struct 用の実験的な Rust → MoonBit typed binding codegen
- Rust を使わず default format の encode と schema-directed zero-copy view を行う、実験的な MoonBit
  schema（JavaScript target を含む）
- format flag、payload length、CRC-32、untrusted input 用 payload 上限を持つ optional な `RMBT` v1 envelope

## 使い方

```moonbit nocheck
import {
  "mizchi/rkyv" @rkyv,
}

let reader = @rkyv.Reader::new(archive_bytes)
let view = reader.read_vec_u32(archive_bytes.length() - 8) catch {
  error => abort("invalid rkyv archive: \{error}")
}
```

失敗しうる Reader と generated view の API はすべて `RkyvError` を raise します。信頼済み archive には
lazy な `View::root` を使えます。信頼できない入力には generated view の `View::validate(bytes)` を使ってください。
対応 field 全体を走査し、pointer・collection span・UTF-8・canonical な bool / `Option` / enum tag を検証し、再帰は
256 段で打ち切ります。返すのは同じ zero-copy view です。これは対応済み schema に限定した検証であり、任意の
rkyv type に対する Rust `bytecheck` の完全な代替ではありません。

### Transport envelope

file、network、cache から受け取る bytes は、通常の rkyv payload を optional な `RMBT` v1 envelope で
包めます。format、payload length、CRC-32 を記録し、`decode_envelope_with_limit` は payload を copy する前に
呼び出し側の上限を超える宣言 length を拒否します。envelope を確認してから generated validator へ payload を渡します。

```moonbit nocheck
let envelope = @rkyv.encode_envelope(archive)
let decoded = @rkyv.decode_envelope_with_limit(envelope, 16 * 1024 * 1024) catch {
  error => abort("invalid archive transport: \{error}")
}
let view = @catalog.CatalogView::validate(decoded.payload_bytes()) catch {
  error => abort("invalid rkyv archive: \{error}")
}
```

collection の主 API は `read_vec_u32`、`read_vec_u32_length`、`read_vec_u32_into`、
`U32VecView::copy_into` です。正常系では error wrapper を生成せず、先に archive 全体を検証します。

```moonbit nocheck
let view = reader.read_vec_u32(root_offset) catch {
  error => abort("invalid rkyv archive: \{error}")
}
let selected = view.get(index)
```

局所的に回復する必要がある場合も `try` / `catch` を使います。`U32VecView::get` と
`U32VecView::at` が `None` を返すのは logical index が範囲外のときだけで、archive の検証失敗は常に
`RkyvError` を raise します。

`reader.read_bytes_view(offset, length)` は範囲だけを検証してコピーなしの `BytesView` を返します。
rkyv の上位 layout や UTF-8 は検証しないため、検証済み `String` が必要な場合は `read_string` を
使います。

## MoonBit schema の生成と JavaScript client

`.mbtx` script を source of truth として、型付き MoonBit package を生成し、その package を client
から import します。これにより application code に dynamic な `Schema` / `Value` を出さず、Rust
なしで archive API を使えます。

### host-defined schema を直接書く場合

小さい archive や一度きりの schema なら、MoonBit に直接定義できます。`Schema::Struct` の field
定義順が archive layout contract です。`Value::Struct` は encode 前に field 数と field 名の両方を
検証し、schema と異なる場合は `SchemaError` を raise します。

この直接 DSL は field 名と schema を値として扱うため runtime-checked です。caller 側でも field と
値型を compile-time に固定したい場合は、後述する generated API を使います。

```moonbit nocheck
///|
let user = @rkyv.Schema::Struct([
  { name: "id", schema: @rkyv.Schema::U32 },
  { name: "active", schema: @rkyv.Schema::Bool },
  { name: "name", schema: @rkyv.Schema::String },
  { name: "scores", schema: @rkyv.Schema::VecU32 },
])

///|
let archive = user.encode(
  @rkyv.Value::Struct([
    { name: "id", value: @rkyv.Value::U32(42U) },
    { name: "active", value: @rkyv.Value::Bool(true) },
    { name: "name", value: @rkyv.Value::String("Ada") },
    { name: "scores", value: @rkyv.Value::VecU32([7U, 11U, 13U]) },
  ]),
) catch {
  _ => abort("schema and value do not match")
}
```

`root` は schema に従った zero-copy `View` を返します。vector は caller が `Array` 化を要求するまで
materialize されません。

```moonbit nocheck
///|
let root = user.root(archive) catch { _ => abort("invalid archive") }

///|
let name = root.field("name")

///|
let scores = root.field("scores")
```

### archive の in-place 更新

archive buffer を caller-owned に保つ場合は `encode_mut` を使います。`root_mut` は root を検証して
`MutView` を返し、data を再配置しない setter だけを提供します。`set_u32`、`set_bool`、UTF-8 byte 長が
同じ場合の `set_string`、既存 vector index に対する `vec_u32_mut().set` が使えます。string や vector の
長さを変える場合は archive 全体を再 encode します。

```moonbit nocheck
///|
let archive = user.encode_mut(
  @rkyv.Value::Struct([
    { name: "id", value: @rkyv.Value::U32(42U) },
    { name: "active", value: @rkyv.Value::Bool(true) },
    { name: "name", value: @rkyv.Value::String("Ada") },
    { name: "scores", value: @rkyv.Value::VecU32([7U, 11U, 13U]) },
  ]),
)

///|
let root = user.root_mut(archive.mut_view())

///|
match root.field("id") {
  Some(id) => ignore(id.set_u32(99U))
  None => abort("missing id")
}

///|
match root.field("scores") {
  Some(scores) => match scores.vec_u32_mut() {
    Some(scores) => ignore(scores.set(1, 42U))
    None => abort("scores is not Vec<u32>")
  }
  None => abort("missing scores")
}
```

[`examples/host_codegen/user_schema.mbtx`](examples/host_codegen/user_schema.mbtx) が input schema を
定義し、[`examples/host_codegen/generated/user.mbt`](examples/host_codegen/generated/user.mbt) を出力します。

```moonbit nocheck
let user = {
  name: "User",
  fields: [
    { name: "id", typ: UInt32 },
    { name: "active", typ: Bool },
    { name: "name", typ: Text },
    { name: "scores", typ: UInt32Array },
  ],
}
emit_schema(user)
```

JavaScript client は生成済み API だけを import します。生成 package は schema 固有の `UserView` と
`UserMutView` を公開するため、caller は field 名を渡せず、getter / setter の型も source schema から
固定されます。`encode` は常に caller-owned な `Array[Byte]` を返すため、read-only view を開くときは
`Bytes::from_array` で明示的に変換します。

```moonbit nocheck
///|
import {
  "mizchi/rkyv/examples/host_codegen/generated" @user,
}

///|
let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U])

///|
let root = @user.UserView::root(Bytes::from_array(archive))

///|
let name : String = root.name()

///|
let scores : @rkyv.U32VecView = root.scores()
```

in-place 更新では、生成された mutable view が valid な setter だけを公開します。

```moonbit nocheck
///|
let archive = @user.encode(42U, true, "Ada", [7U, 11U, 13U])

///|
let writer = @user.UserMutView::root(archive.mut_view())

///|
writer.set_id(99U)
writer.set_active(false)
let patched : Bool = writer.set_name_same_length("Eve")
let scores = writer.scores_mut()
ignore(scores.set(1, 42U))
```

source schema を変更したら再生成します。`host-js` はまず生成物が source と一致することを確認してから、
client を JS target だけで実行します。

```sh
just host-schema
just host-js
# Eve: 3 scores
```

現時点の generator は `u32`、`bool`、`String`、`Vec<u32>` の field に対応します。field の定義順を
layout contract とします。既存の任意 Rust `Archived<T>` の field offset を推論するものではないため、
同じ schema を Rust type と共有する場合は Rust との byte 比較で確認するか、Rust layout codegen を使ってください。

## ドッグフーディング: static product catalog

[`examples/catalog`](examples/catalog) は production を想定した end-to-end の例です。Rust の build step が
`Catalog { products: Vec<Product> }` を所有し、実データを rkyv で archive 化した上で、`RkyvMbt` から正確な
MoonBit view を生成します。JavaScript target の client は最小の Node `Buffer -> Bytes` loader 経由で
checked-in `.rkyv` binary を開き、JSON を parse したり product の `Array` を materialize したりせず、
`Vec<Product>` を lazy に検索します。

生成 package には `ProductInput` と `CatalogInput` も含まれます。`Vec<Product>`、`Vec<String>`、
`Option<u32>` を含むこの schema について、MoonBit → Rust も型付きで encode できます。

```sh
just catalog-generate
moon test --target js examples/catalog/client
just catalog-js
# Moon Mug: 1800 cents
just catalog-roundtrip
```

`just conformance` に含まれる `check-catalog` が、Rust type・生成 view・archive fixture の同期を検証します。
`catalog-roundtrip` は MoonBit の `CatalogInput::encode()` で archive を書き、Rust の `rkyv::access` で
検証して値まで確認します。

## ベンチマーク

4,096 要素の `Vec<u32>` を native release で測定しました。archive は測定ループ外で一度だけ構築
しています。MoonBit は benchmark の平均値、Rust は Criterion の 95% confidence interval なので、
命令単位の厳密比較ではなく end-to-end の参考値です。

環境: arm64、macOS 26.5.2、Moon 0.1.20260713 / moonc 0.10.4、Rust 1.96.0、rkyv 0.8.17。

| 操作 | MoonBit native | Rust rkyv native |
| --- | ---: | ---: |
| checked header + length validation | **6.33 ns** | 3.01 ns |
| 検証済み lazy view から 1 要素を読む | **6.84 ns** | 1.44 ns |
| checked root + 1 要素の lazy read | **9.81 ns** | 3.32 ns |
| 4K 要素すべての checked eager materialization | 478.40 ns | 256.22 ns |
| 検証済み view から再利用 `FixedArray` / Rust `Vec` への copy | 200.39 ns | 200.15 ns |
| checked で再利用 `FixedArray` / Rust `Vec` へ copy | **198.22 ns** | 201.11 ns |
| 再利用 `MutArrayView` への copy | 1.50 µs | — |

Rust 側は public checked API の `rkyv::access` を使っています。両側とも同じ encode 済み 4K `Vec<u32>`
archive を受け取り、archive 構築は測定 loop の外です。MoonBit は `--target native` です。runtime、allocation、
compiler optimization を含む値なので、導入判断時は対象環境で再計測してください。

```sh
just bench
just bench-profile
just bench-compare
just profile
just host-js
```

throughput が重要なら、複数の `get` には `U32VecView` を保持し、再利用 buffer には
`FixedArray` と `copy_into` を使ってください。growable `Array` が不要なら `to_array_fast()` より
`to_fixed_array_fast()` が二段目の copy を避けられます。`MutArrayView` は部分範囲を書けますが
native bulk-copy 経路ではありません。

## Rust との相互運用性

`just conformance` は両方向を byte 単位で検証します。

- Rust `rkyv::to_bytes` の出力を MoonBit が読めること
- MoonBit `encode_vec_u32` / `encode_string` の出力を Rust `rkyv::access` が受理すること
- catalog example で nested struct、primitive vector、`Vec<String>`、`Option<Vec<T>>`、fieldless enum の
  MoonBit → Rust archive を検証すること

任意の `#[derive(Archive)]` struct、tuple、enum、generic collection、一般の `Vec<T>` は公開された
互換性保証には含みません。

## 型付き codegen（実験的）

`codegen/rust` の `RkyvMbt` derive は、Rust compiler が確定した `Archived<T>` の size と field offset を
使って MoonBit typed view を出力します。numeric primitive、`bool`、`String`、`Vec<primitive>`、`Vec<String>`、nested な
derive 済み named struct とその vector、`Option<Vec<T>>` を含む一段の `Option<T>` に対応しています。fieldless enum は
`RkyvMbtEnum` により strict tag view と type-safe writer を生成します。

`render_moonbit_with_encoder()` は `TypeInput::new` と `TypeInput::encode` も生成します。書き込み対象は
対応する全 struct field を書き込めます。writer は field 定義順から layout を再計算せず、Rust compiler が確定した
field offset と `Archived<T>` size をそのまま使います。

Rust crate は実験的で、crates.io には公開していません。対応 format と使用法は
[codegen/rust/README.md](codegen/rust/README.md) を参照してください。

## 開発

```sh
just fmt
just check
just test
just conformance
just codegen
```

## License

Apache-2.0。 [LICENSE](LICENSE) を参照してください。
