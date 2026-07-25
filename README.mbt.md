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
- `ArchivedVec<u32>` の zero-copy lazy view と、必要時だけ行う配列への materialize
- 32-bit shared memory bridge 向けの `ArchivedVec<u32>` 要素先頭 byte offset
- rkyv 0.8 の inline / out-of-line `ArchivedString`
- デフォルト形式での root `Vec<u32>` と `String` のエンコード
- little-endian / big-endian のプリミティブ読み取りと pointer width 16 / 32 / 64 の Reader

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
just conformance
```

`just bench` は release ビルドで、4,096 要素の `Vec<u32>` に対する「中央の 1 要素を
lazy に読む」経路と「全要素を配列化する」経路を同じ入力で計測します。実行環境・MoonBit の
target・最適化によって数値は変わるため、比較時は同じ target で再計測してください。

## Rust との相互運用性

リリース時の保証範囲は **rkyv 0.8.17 のデフォルト形式**（little-endian / aligned /
pointer width 32）で、root の `Vec<u32>` と `String` です。`just conformance` は次の
両方向をバイト単位で検証します。

- Rust の `rkyv::to_bytes` が生成した値を MoonBit の `Reader` が読めること
- MoonBit の `encode_vec_u32` / `encode_string` の出力を Rust の `rkyv::access` が受理すること

任意の `#[derive(Archive)]` struct / tuple / enum や一般の `Vec<T>` は、MoonBit バインディング
codegen を実装するまでこの保証範囲に含めません。詳細な契約と Rust 側の固定バージョンは
[`conformance/README.md`](conformance/README.md) にあります。

## 次の段階

- Rust の `Archive` derive から MoonBit バインディングを出力する codegen
- struct / tuple / enum / array のレイアウト生成
- `Vec<T>`、pointer、map collection の型付きデコーダと lazy view
- Rust の `bytecheck` を使う、より広い型集合の双方向 conformance suite

この段階では、ランタイムの wire-format API を安定した契約層に留め、生成コードは再生成可能な
実装層として追加する方針です。
