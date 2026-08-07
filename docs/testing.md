# テスト設計

同じ契約を複数のテスト層へ複製せず、各境界の正本を1つにする。別の層では正本の具体値を再列挙せず、その層で初めて生じる統合だけを検査する。

## 責務の分け方

| 層 | 責務 |
| --- | --- |
| Pure Nix | module option、評価時の不変条件、生成値 |
| Unit・library integration | domain logic、property、transaction、rollback、idempotence |
| Process integration | CLI、stdin・stdout・終了status、child process境界 |
| Nix-backed integration | 公開binary、Nix store wiring、実際の外部process、platform差異 |
| Workflow lint | GitHub Actionsの汎用的な構文とsecurity |
| Workflow policy | このrepositoryだけが所有するCI上の契約 |
| Live test | upstream APIや配布物など、固定できないnetwork contract |

sourceを直接使うテストは短いfeedbackのための補助とし、packageされた成果物のintegrationを代替させない。

## Assertionの粒度

次の境界では、完全一致やexact inventoryを維持する。

- 公開serializationと設定ファイルのbyte表現
- security allowlistと閉じたexport namespace
- child processのargv protocolと終了status
- file mode、atomic write、rollback後のbytes

一方、追加可能なsettings、filesystem discovery、production registryの内容を別のテスト層へ再列挙しない。追加を許す集合は、一意性、schema、参照整合性、round-tripなどのpropertyで検査する。

負例は「失敗したこと」だけでなく、意図したerror identityを検査する。platform非対応のチェックはdummy passにせず、checkを生成しないか、実行側で理由付きskipにする。

Live testは、再現可能なcommit gateへ混在させない。上流の状態を固定できない失敗とrepositoryの退行を区別できなくなるためである。

## Nix式のmutation test

mutation testは、テスト対象の振る舞いを意図的に変え、その変更を関連テストが検出できるか確認するために使う。利用方法と終了statusはCLIのhelpを参照する。

```bash
nix develop --command nix-mutation-test --help
```

対象の契約を所有する最小のcheckを関連テストとして選ぶ。正例と負例が別のcheckに分かれている場合は両方を実行し、正常系の退行と異常系の受理をどちらも検出できるようにする。

mutation testは候補ごとにテストを再実行するため、通常のcommit gateには含めない。条件分岐やテストを変更した後に、テストが期待する契約を観測できているか診断する用途で実行する。

## Dendritic moduleとテストの境界

Dendritic moduleでは、自動importされる構成moduleと、テスト用のsupport codeの探索範囲を分離する。具体的な配置規則は実装と検査を正本とし、この文書には列挙しない。

この境界は命名規則だけに依存させず、構成moduleとsupport codeが交差しないことをarchitecture checkで検査する。構成の意味は評価結果のcontractで検査し、source検査だけで代替しない。
