# UEFN Verse Library — Scene Graph の部品集

[English](README.md) | 日本語

UEFN（Fortnite クリエイティブ）の Scene Graph（entity / component）で、組み合わせて使う Verse の部品集です。カウントダウン・ゲームの流れ・能力・アイテム・独自キャラクター・画面（HUD）・MCP によるライブ編集など、`<名前>System/` ごとに 1 つの仕組みを持ち、差し替え部品を `Kit` として足せます。対象は UEFN **v43.00** 以降。

- ライブラリのバージョン: **0.1.0**（`VERSION`・`CHANGELOG.md`）
- 本体は [`Library/`](Library/)。中身・設計の決まり・確かめ方は [Library/README.md](Library/README.md)、各 System の使い方はその System の `README.md`（MCPSystem だけ `README.md` が英語、`README.ja.md` が日本語）

> **非公式**のものです。Epic Games とは関係がなく、Epic Games の承認も受けていません（Verse・Unreal Engine・UEFN・Fortnite はいずれも Epic Games のものです）。

## 入れ方

1. `Library/` フォルダを、UEFN プロジェクトの Verse のフォルダに置きます（作者は `Content\VerseCode\Library` に置いています）。
2. UEFN で Verse をビルドします。`LibraryModules.verse` にすべての System の `module` 宣言があります。
3. 使う System の component を entity に付けます。置き方は各 System の `README.md` と、component の先頭コメント（役割 / 置き方 / 親 / 子 / 同じ entity / 前提）にあります。

- 名前が `ExperimentalKit` で終わるフォルダは `@experimental` の API を使っています。公開する島では使えないので、要らなければ消してください。
- `_Test/` は UEFN 上で動かす動作確認、`_Samples/` は置いて試す見本です。どちらも公開 API だけで書いてあるので、使い方の見本になります。

## 状態

0.x のあいだは整理中で、公開 API が変わることがあります。既知の問題は [CHANGELOG.md](CHANGELOG.md)（英語）に書きます。

## バージョンの決まり

`vA.B.C` で付けます（git のタグも同じ）。

| 桁 | 上がるとき |
|---|---|
| A | 破壊的変更が含まれる（公開 API の名前・型・振る舞いが変わり、利用側のコードを直さないと動かない） |
| B | 新機能の追加（System・Kit・公開 API の追加。場合によっては利用側のコードの修正が必要） |
| C | バグ修正 |

## ライセンス

[MIT License](LICENSE)。Verse・Unreal Engine・UEFN・Fortnite は Epic Games, Inc. の商標または登録商標です。
