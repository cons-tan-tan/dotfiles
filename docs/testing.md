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

## Dendritic moduleとテストの境界

`modules/`では、pathに`/_`を含まないNixファイルを構成moduleとして自動importする。純粋関数、fixture、評価テストは`_lib/`または`_tests/`へ置き、構成moduleと同じtreeで管理しつつ自動importの対象外にする。

この境界は命名規則だけに依存させない。test discoveryがsupport directory内のテストを収集し、architecture gateがmodule treeとの非交差、旧composition pattern、包括的なunfree許可の不在を検査する。構成の意味は評価結果のcontractで検査し、source検査だけで代替しない。
