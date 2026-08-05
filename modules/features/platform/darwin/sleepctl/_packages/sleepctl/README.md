# sleepctl

`sleepctl`は、macOSで時間制限付きのスリープ抑止を扱うためのCLIと
LaunchDaemonである。通常のidle sleepは`caffeinate`に任せ、蓋を閉じた状態を
またぐ処理だけを、root daemonが所有するleaseとして管理する。

## 設計意図

`SleepDisabled`はsystem全体へ影響するため、呼び出したprocessの終了処理だけに
復元を任せない。daemonが期限、clientとの接続、durable sentinelを管理し、異常
終了後も通常のsleep状態へ戻せる構成にしている。

安全判定にはmacOSが公開する定性的なthermal stateを使う。private sensorの値や
推測した摂氏温度には依存しない。thermal stateやbatteryを安全に確認できない
場合を含め、閉じた蓋をまたぐleaseは安全側に倒す。この安全機構を無効化する
optionは設けない。

具体的な閾値、状態遷移、protocol fieldは実装とtestを正本とする。安全判定は
[`src/model.rs`](src/model.rs)、protocolは[`src/protocol.rs`](src/protocol.rs)、
特権状態の遷移順序は[`src/daemon.rs`](src/daemon.rs)を参照する。

## 利用

正確な引数構文は、導入されているbinaryのhelpを参照する。安全上の制約は実行時に
検証されるため、固定値を前提にせずerror messageとstatusを確認する。

```sh
sleepctl --help
sleepctl run --help
sleepctl hold --help
```

代表的な利用方法は次のとおりである。

```sh
# idle sleepを期限付きで抑止する
sleepctl run --for 3h -- command arg

# 蓋を閉じた状態をまたぐleaseでcommandを実行する
sleepctl run --lid-closed --for 3h -- command arg

# commandを起動せずにleaseを保持する
sleepctl hold --lid-closed --for 30m
```

lid leaseには必ず期限がある。通常の期限切れではsleep抑止だけを終了し、実行中の
commandは継続する。安全trip、operatorによる停止、またはclientとの接続や
heartbeatを確認できない場合は、安全側に倒すため対象のcommandも停止する。

scriptから判定できるよう、sleepctl自体の終了状態はusage error`2`、daemonとの
通信失敗`3`、安全上の拒否またはdiagnostic error`4`、安全trip`5`、
cleanup失敗`6`、operator停止`7`に分ける。cleanupが成功した通常経路では、
実行したcommandが先に終了した場合はその終了状態を返し、signalを受けた場合は
shellと同じ`128 + signal`を返す。安全な復元やprocessの回収に失敗した場合は、
元の終了状態よりcleanup失敗を優先する。

## 状態確認と復旧

日常の確認には、次のcommandを使う。

```sh
sleepctl status
sleepctl status --json
sleepctl doctor
sleepctl stop --all
sleepctl recover
```

`doctor`は状態を変更しない。daemon、公開thermal API、固定された電源管理
command、state directoryを読み取り専用で検査する。sleepctlが所有していない
`SleepDisabled`を検出した場合はforeign stateとして報告し、自動では変更しない。

daemonのlogは`/var/log/sleepctld.log`と`/var/log/sleepctld.err.log`にある。
通常の復旧手順が失敗し、`SleepDisabled`が残った場合だけ、operatorが次の固定
commandで解除し、IORegistryのread-backを確認する。

```sh
sudo /usr/bin/pmset -a disablesleep 0
/usr/sbin/ioreg -r -k SleepDisabled -d 4
```

thermal tripのtestとして、hardwareを意図的に高温にしたり、batteryを意図的に
消耗させたりしない。安全分岐はfake sourceを使う自動testで検証する。
