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

双方向の互換性保証は現在 root の `Vec<u32>` と `String` に限ります。実行可能な契約と制約は
[conformance/README.md](conformance/README.md) を参照してください。

## 機能

- デフォルト rkyv format の bounds-checked Reader
- `u8`〜`u64`、`i8`〜`i64`、`f32`、`f64`、`bool` の bit-compatible な読み取り
- relative pointer、`ArchivedVec<T>` header、`ArchivedOption<T>` value offset
- archive の任意範囲をコピーせず借用する bounds-checked `BytesView`
- `ArchivedVec<u32>` の zero-copy lazy view、`Array` / `FixedArray` への materialize、再利用 buffer への copy
- root `Vec<u32>` と `String` のデフォルト format encoder
- little-endian / big-endian と pointer width 16 / 32 / 64 の primitive reader
- named struct 用の実験的な Rust → MoonBit typed binding codegen
- Rust を使わず default format の encode と schema-directed zero-copy view を行う、実験的な MoonBit
  schema（JavaScript target を含む）

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

失敗しうる Reader と generated view の API はすべて `RkyvError` を raise します。archive 境界で
一度だけ catch し、検証済みの zero-copy view を以降の処理へ渡してください。信頼できない入力に
対する Rust の `bytecheck` を完全に置き換えるものではありません。

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

## ベンチマーク

4,096 要素の `Vec<u32>` を native release で測定しました。archive は測定ループ外で一度だけ構築
しています。MoonBit は benchmark の平均値、Rust は Criterion の 95% confidence interval なので、
命令単位の厳密比較ではなく end-to-end の参考値です。

環境: arm64、macOS 26.5.2、Moon 0.1.20260713 / moonc 0.10.4、Rust 1.96.0、rkyv 0.8.17。

| 操作 | MoonBit native | Rust rkyv native |
| --- | ---: | ---: |
| checked root + 1 要素の lazy read | **9.76 ns** | 2.70 ns |
| 4K 要素すべての checked eager materialization | 464.57 ns | 259.06 ns |
| 再利用 `FixedArray` / Rust `Vec` への copy | 192.32 ns | 204.51 ns |
| 再利用 `MutArrayView` への copy | 1.52 µs | — |

Rust 側は public checked API の `rkyv::access` を使っています。MoonBit は `--target native` です。
runtime、allocation、compiler optimization を含む値なので、導入判断時は対象環境で再計測してください。

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

任意の `#[derive(Archive)]` struct、tuple、enum、generic collection、一般の `Vec<T>` は公開された
互換性保証には含みません。

## 型付き codegen（実験的）

`codegen/rust` の `RkyvMbt` derive は、Rust compiler が確定した `Archived<T>` の size と field offset を
使って MoonBit typed view を出力します。numeric primitive、`bool`、`String`、`Vec<u32>`、nested な
derive 済み named struct とその vector を持つ named struct に対応しています。対応する direct field は
`Option<T>` にもできますが、`Option<Vec<T>>` は未対応です。

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
