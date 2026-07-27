# mizchi/rkyv

rkyv 0.8 のアーカイブを MoonBit から読むための、小さく安全なランタイムです。
Rust 側で `rkyv` が生成したバイト列をコピーせずに参照し、スキーマ固有のコードは
生成済みバインディングまたはアプリケーション側に分離することを目的にしています。

設計は [cometkim/rkyv-js](https://github.com/cometkim/rkyv-js) の二段階の考え方、すなわち
「共有ランタイム」と「Rust の型から生成するバインディング」を参考にしています。

## 現在の機能

- デフォルトの rkyv 0.8 形式（little-endian / pointer width 32 / aligned）の安全な Reader
- `u8`〜`u64`、`i8`〜`i64`、`f32`、`f64`、`bool` のビット互換な読み取り
- rkyv の相対ポインタ、`ArchivedVec<T>` ヘッダ、`ArchivedOption<T>` の値オフセット
- `ArchivedVec<u32>` の zero-copy lazy view、配列への materialize、再利用バッファへの copy
- 32-bit shared memory bridge 向けの `ArchivedVec<u32>` 要素先頭 byte offset
- rkyv 0.8 の inline / out-of-line `ArchivedString`
- デフォルト形式での root `Vec<u32>` と `String` のエンコード
- little-endian / big-endian のプリミティブ読み取りと pointer width 16 / 32 / 64 の Reader
- Rust の named struct から型付き MoonBit view を出力する experimental codegen

`rkyv-js` が Rust で生成している rkyv 0.8.14 の primitive / option fixture をテストに取り込み、
デフォルトレイアウトの互換性を固定しています。

## 使い方

```moonbit nocheck
import {
  "mizchi/rkyv" @rkyv,
}

let reader = @rkyv.Reader::new(archive_bytes)
let header = reader.read_vec_header(archive_bytes.length() - 8)
```

`Reader` は bounds check を行い、範囲外アクセスを `RkyvError` として返します。
ただし Rust の `bytecheck` と同等の完全な検証器ではありません。信頼できない入力は Rust 側で
`bytecheck` を実行するか、用途に応じた追加検証を行ってください。

## 開発

```sh
just test
just check
just fmt
just info
just bench
just profile
just conformance
```

`just bench` は release ビルドで、4,096 要素の `Vec<u32>` に対する「中央の 1 要素を
lazy に読む」経路と「全要素を配列化する」経路を同じ入力で計測します。実行環境・MoonBit の
target・最適化によって数値は変わるため、比較時は同じ target で再計測してください。

Rust rkyv との native 比較は `just bench-compare` で実行できます。MoonBit は
`--target native`、Rust は Criterion の release benchmark を使い、どちらも archive は計測外で
一度だけ構築します。各反復では安全な root access と中央要素の読み取り、または安全な root access
と 4,096 要素の owned collection 化を行います。Rust は `rkyv::access`（bytecheck を伴う public safe
API）を用います。なお、これは言語ランタイム・配列実装・コンパイラ最適化を含む end-to-end 比較であり、
wasm-gc/JS target の MoonBit 性能や同一 ABI での純粋なアルゴリズム比較を表すものではありません。

現在の Moon CLI には `moon bench --profile` はありません。`just bench-profile` は代わりに
Reader 生成・Vec header/span 検証・検証済み view の `get` を個別に計測します。`just profile` は
`moon run --profile --release --target native cmd/profile` を実行し、header 検証・lazy access・eager
materialization・再利用バッファへの copy を Time Profiler（macOS）で十分長く反復します。通常の利用では
`read_vec_u32` の結果を保持し、複数の要素を `get` で読むと header 検証コストを一度にできます。

`Reader::read_vec_u32` が返す `U32VecView` は生成時に全要素の byte span を検証済みです。
そのため `view.get(index) -> UInt?` は有効な index の追加範囲検証なしに値を読みます。既存の
`view.at(index) -> Result[UInt?, RkyvError]` と `view.to_array()` もこの fast path を内部利用し、
互換性を保ちます。`view.to_array_fast() -> Array[UInt]` は検証済み view 専用の non-failing API で、
native target の little-endian では最適化済み bulk copy を使い、JS / wasm-gc などの他 target では
experimental `moonbitlang/core/v128` で 16 bytes（4要素）ずつ読みます。big-endian format は scalar
fast path を使います。

確保済みのバッファを複数回使う場合は、`FixedArray[UInt]` を渡す
`view.copy_into(destination) -> Result[Unit, RkyvError]` を使えます。宛先は view の要素数以上で
ある必要があり、不足時は `DestinationTooSmall` を返して一切書き込みません。native の
little-endian では `to_array_fast` と同じ bulk copy を使うため、反復ごとの配列確保を避けられます。

要素数だけが必要な場合は
`reader.read_vec_u32_length(offset) -> Result[Int, RkyvError]` を使えます。
この API も全要素 span を検証しますが、`U32VecView` を生成・保持しません。

デフォルトの rkyv format（little-endian / pointer width 32）では `read_vec_u32` も 8-byte header を
一度だけ検証する専用経路を使います。big-endian または pointer width 16 / 64 を指定した `Reader` は、
同じ公開 API から従来の汎用検証経路へ自動的にフォールバックします。

## Rust との相互運用性

リリース時の保証範囲は **rkyv 0.8.17 のデフォルト形式**（little-endian / aligned /
pointer width 32）で、root の `Vec<u32>` と `String` です。`just conformance` は次の
両方向をバイト単位で検証します。

- Rust の `rkyv::to_bytes` が生成した値を MoonBit の `Reader` が読めること
- MoonBit の `encode_vec_u32` / `encode_string` の出力を Rust の `rkyv::access` が受理すること

任意の `#[derive(Archive)]` struct / tuple / enum や一般の `Vec<T>` は、MoonBit バインディング
codegen を実装するまでこの保証範囲に含めません。詳細な契約と Rust 側の固定バージョンは
[`conformance/README.md`](conformance/README.md) にあります。

## 型付き codegen（開発中）

`codegen/rust` には、Rust コンパイラが確定した `Archived<T>` の size と field offset を使って
MoonBit view を出力する `RkyvMbt` derive があります。最初の対応型は named struct 内の整数・浮動小数点
primitive、`bool`、`String`、`Vec<u32>`、および derive 済み named struct の `Vec` です。生成済み view は
offset を公開せず、通常の MoonBit API として root と field accessor を提供します。derive 済みの named struct
を field に含めると、同じ archive を参照する nested view を生成します。`Vec<named struct>` は要素全体の範囲を
先に検証し、`at(index)` を呼んだ要素だけ nested view に変換します。対応型を包む `Option<T>` は MoonBit の
nullable result として生成されます（`Option<Vec<T>>` はまだ未対応です）。

この Rust workspace はまだ crates.io へ公開していません。利用方法と format profile の制約は
[`codegen/rust/README.md`](codegen/rust/README.md) を参照してください。`just codegen` で Rust の
layout 抽出・source 出力を、`just conformance` で生成 view を含む両言語の検証を実行します。

## 次の段階

- Rust の `Archive` derive から MoonBit バインディングを出力する codegen
- tuple / enum / array のレイアウト生成
- `Option<Vec<T>>`、array、pointer、map collection の型付きデコーダと lazy view
- Rust の `bytecheck` を使う、より広い型集合の双方向 conformance suite

この段階では、ランタイムの wire-format API を安定した契約層に留め、生成コードは再生成可能な
実装層として追加する方針です。
