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
