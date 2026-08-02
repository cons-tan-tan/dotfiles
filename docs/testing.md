# テストの責務と実行方法

テストでは、同じ入力一覧を複数の層へ複製せず、各境界の正本を1つにする。変更時は最も狭い関連テストを先に実行し、commit前にrepository gateを実行する。

## 責務の分け方

| 層 | 正本にする内容 | 主な実行方法 |
| --- | --- | --- |
| Pure Nix | module option、設定の不変条件、package構成、生成値 | `*.test.nix`から生成されるflake check |
| Rust unit・library integration | domain logic、registry property、transaction、rollback、idempotence | crateごとの`cargo test` |
| Rust process integration | CLI parse、実行ファイルのstdin・stdout・終了status、child process境界 | crateのintegration test |
| Nix-backed Bats | Nix-built public binary、Nix store wiring、real Git、host portability | `bats-tests` aggregate |
| Raw Bats | repository内のsource scriptを素早く確認する補助テスト | `bats --print-output-on-failure tests/` |
| Workflow lint | GitHub固有構文、SchemaStore構造、inline shell、security | `workflow-lint-tests` |
| Workflow policy | cache、Hestia、credential、smoke順序などrepository固有の契約 | `workflow-policy-tests` |
| Scheduled live test | upstream API、配布物、network contract | 定期workflow |

Raw Batsでは、Nix packageだけで成立するテストを理由付きでskipする。そのため、raw実行の成功はpackage integrationの成功を意味しない。

## Assertionの粒度

次の境界では、完全一致やexact inventoryを維持する。

- 公開serializationと設定ファイルのbyte表現
- security allowlistと閉じたexport namespace
- child processのargv protocolと終了status
- file mode、atomic write、rollback後のbytes

一方、追加可能なsettings、filesystem discovery、production registryの内容を別のテスト層へ再列挙しない。追加を許す集合は、一意性、schema、参照整合性、round-tripなどのpropertyで検査する。

負例は「失敗したこと」だけでなく、意図したerror identityを検査する。Pure Nixのvalidation負例には`*.failure.test.nix`を使い、子evaluatorのroot diagnosticを確認する。platform非対応のチェックはdummy passにせず、checkを生成しないか、実行側で理由付きskipにする。

## 正規のコマンド

Nixの全system評価とformatは、次をcommit gateとする。

```bash
nix flake check --no-build --all-systems
nix run .#fmt -- --ci
```

各systemで利用可能なRust project全体は、catalogから生成した3つのcheckを使う。次はx86_64-linuxの例であり、Darwin専用crateはaarch64-darwinの同名checkに含まれる。

```bash
nix build --no-link .#checks.x86_64-linux.rust-tests
nix build --no-link .#checks.x86_64-linux.rust-clippy
nix build --no-link .#checks.x86_64-linux.rust-advisories
```

開発中はcrateを絞れる。featureがあるcrateでは、Nix catalogと同じflagsを指定する。

```bash
cargo test --manifest-path nix/apps/update-pins/Cargo.toml --all-targets --features smoke
```

Batsの正規gateは、Nixがfixtureとpublic binaryを注入するaggregateである。

```bash
nix build --no-link .#checks.x86_64-linux.bats-tests
```

GitHub Actionsの検査は、汎用validatorとrepository固有policyを分けて実行する。

```bash
nix build --no-link .#checks.x86_64-linux.workflow-lint-tests
nix build --no-link .#checks.x86_64-linux.workflow-policy-tests
```

`workflow-lint-tests`は`gha-lint`とzizmorを再現可能な環境で実行する。通常の`gha-lint`は実行時に最新のSchemaStore schemaを取得するが、Nix gateでは固定したschema fixtureを注入する。GitHub公式language serviceは式やcontext、matrix、local reusable workflow、parallel/background構文を検査する。AjvとSchemaStoreは構造を独立して検査する。ShellCheckはworkflowとcomposite actionのinline shellを担当する。zizmorはpermissions、credential、template injection、action pinなどを検査する。

`workflow-policy-tests`は、このrepositoryのcache設定、Hestia matrix、checkout credential、update-pins smokeの順序をBatsで検査する。汎用validatorのdiagnostic文言は、この層で再検査しない。

`bats --print-output-on-failure tests/`は、source-onlyテストを素早く回すための補助コマンドである。Nix fixtureを必要とするテストはskipされるため、このコマンドだけでcommit gateを代替しない。

Live networkを使う確認は、再現可能なcommit gateへ混在させず、scheduled workflowに置く。
