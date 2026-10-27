# SafeKeys

擦 Mac 键盘时，把键盘锁住；一个按钮锁，另一个按钮解。

macOS 15.6 / Apple Silicon，纯 Swift + AppKit/SwiftUI，**不需要 Xcode**，无第三方依赖，无联网、无数据收集。

---

## 快速开始

```bash
cd SafeKeys
./scripts/build-app.sh      # 编译并生成 dist/SafeKeys.app
```

然后把 `dist/SafeKeys.app` 拖到你想长期使用的位置（建议 `/Applications`）。

> ⚠️ **选定位置后就不要再移动它。** 本地未公证 app 用的是 ad-hoc 签名，
> 换路径或重新签名会让 macOS 认为它是另一个程序，辅助功能授权随之失效，需要重新勾选。

### 首次打开

macOS 会因为"无法验证开发者"拦一下，这是本地自签的必然结果：

```bash
xattr -dr com.apple.quarantine /Applications/SafeKeys.app
```

或者：访达里右键 → 打开 → 打开（只需一次）。

### 授权（必须）

1. 打开 SafeKeys，如果主界面显示"需要辅助功能权限"，点 **去设置**
2. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 SafeKeys
3. **完全退出再重新打开 SafeKeys**（macOS 的 TCC 权限只在下次启动时生效）

授权后主界面状态灯变绿，锁定按钮才可用。这是刻意的：**没有权限就绝不进入锁定状态**，
避免出现"以为锁了其实根本没锁"的静默失败。

---

## 用法

主窗口就两个按钮：

| 按钮 | 什么时候可用 |
|---|---|
| **锁定键盘** | 键盘正常时 | 
| **解锁键盘** | 键盘被锁时 |

锁定后会出现一块覆盖全屏的浮层，上面有 **解锁键盘** 大按钮和倒计时。鼠标和触控板从头到尾不受影响。

**三种解锁方式，任意一种都行：**

1. **按住**浮层（或主窗口）上的「按住解锁」按钮 **0.8 秒**（有进度条）—— 单击无效，
   这是为了防擦洗时蹭到触控板误解锁
2. 敲**解锁口令** —— 默认连贯地连按 Esc 四次，口令提示就印在浮层上，不用记
3. 等倒计时结束，默认 90 秒（可改：30 秒 / 60 秒 / 90 秒 / 2 分钟 / 不限时）

> 即使选了"不限时"，**10 分钟后也会强制解锁**。这是硬上限，改不了 —— 防止忘了自己在锁定状态。

### 为什么解锁要设计得这么"麻烦"

因为实际用起来最先出问题的不是解不开，而是**被意外解开**。所以口令加了四道约束，
四条必须同时成立才放行：

| 约束 | 挡掉什么 |
|---|---|
| 必须是**多个**按键 | 蹭到单个键就解锁 |
| 相邻两次间隔在 **0.1–0.8 秒**之间 | 抹布划过去的连击、以及慢吞吞的零星触碰 |
| 序列中途碰了**任何其他键**就重来 | 擦洗时总会有好几个键一起被蹭到；人照着提示敲口令时只会碰到口令里那几个 |
| 按住不放产生的系统**重复事件**不计 | 手压在键上不动会被系统连续上报成多次按下 |
| 另有锁定后 **2 秒冷却期** | 点完锁定、手还没离开键盘那一下的余波 |

口令可以在主界面改，四种可选：

| 选项 | 操作 | 适合谁 |
|---|---|---|
| **Esc ×4**（默认） | 连贯敲四下 Esc | 大多数人 |
| **Tab·Esc 交替** | 依次 Tab → Esc → Tab → Esc | 想要更难误触 |
| **⌘⌥U** | Cmd + Option + U | 习惯用组合键 |
| **不用键盘** | 只能按按钮或等倒计时 | 完全不信任任何键盘输入 |

> 这套判定规则的胜负手在于"错位即重来"。想知道它到底有没有算对，不必去按键：
> 见文末的 `--selftest`。

---

## 如果真的出问题了

按可能性从高到低，**每一条都能让键盘立刻恢复**：

| 情况 | 怎么办 |
|---|---|
| 按钮点不到 | 浮层层级高于普通窗口，不可能被盖住；口令仍然有效 |
| 忘了怎么解锁 | 口令写死在浮层上，看得见就能解 |
| App 崩溃 / 无响应 | `pkill -x SafeKeys` —— 事件拦截是进程资源，**进程一死键盘必然恢复** |
| 强退也麻烦 | 活动监视器里搜 SafeKeys → 强制退出，效果同上 |
| 主线程彻底死锁（极端情况） | 内置看门狗会在 3 秒无心跳后自行释放并退出，无需人工干预 |
| 权限被取消 | 程序检测到后立即自动解锁 |

**万能钥匙：`pkill -x SafeKeys`** —— 这一条记住就够。

---

## 原理

### 怎么锁

在系统 HID 事件层面插一个 `CGEventTap`，回调返回 `nil` 表示"事件已被消费"，事件就再也不会传
到任何 App。掩码覆盖四类：

- `keyDown` / `keyUp` — 普通按键
- `flagsChanged` — Cmd / Shift / Option / Ctrl / CapsLock
- `NX_SYSDEFINED`(14) — 亮度、音量、播放、部分功能键。不写这条，F1–F12 会漏

注入点用 `kCGHIDEventTap`（枚举值 0），是最早的用户态拦截点。

### 覆盖范围

| 输入 | 锁定 |
|---|---|
| 字母数字符号、Enter、空格、Tab | ✅ |
| Cmd+Tab / Cmd+Space / Cmd+Q / Cmd+Opt+Esc / Ctrl+Cmd+Q | ✅ |
| Cmd / Shift / Option / Ctrl / CapsLock | ✅ |
| F1–F12 亮度音量播放（含长按、连按） | ✅ |
| 中英文输入法切换与候选上屏 | ✅ |
| 外接 USB / 蓝牙键盘 | ✅ |
| 鼠标、触控板、手势 | ❌ **保留** —— 这是解锁的物理保障 |
| 电源键 / Touch ID | ❌ 硬件层，公开 API 拦不了 |

### 怎么保证一定能解锁

四条主路径互相独立，加上三条兜底：

- 按住解锁按钮 0.8 秒（鼠标路径）
- 解锁口令（键盘路径，可在设置里选 Esc ×4 / Tab·Esc 交替 / ⌘⌥U / 关闭）
- 倒计时 + 10 分钟硬上限（时间路径）
- **进程终止 = 解锁**（操作系统保证：tap 是进程资源）
- 兜底 1：`atexit` + SIGINT/SIGTERM handler 抢占所有退出路径
- 兜底 2：**独立 pthread 看门狗**，主线程卡死 3 秒即释放 tap 并退出
- 兜底 3：权限被撤销、系统睡眠、锁屏、用户切换 → 自动解锁

唯一真正灾难的场景是"进程活着但主线程卡死"，此时 UI 点不动、键盘也全废。
看门狗线程不依赖 RunLoop，只盯着一个心跳时间戳，专门收拾这个场景。

---

## 退出与资源占用

**关闭窗口即退出进程。** 点红叉等同于 Cmd+Q：先解锁键盘、再释放一切后台设施、进程消失，
不留任何常驻任务。App 的职责是"临时劫持键盘"，用完就该彻底安静。

退出路径上做了三层收尾：

| 时机 | 动作 |
|---|---|
| 关闭窗口 | `windowShouldClose` 先解锁 → `windowWillClose` 主动 `NSApp.terminate` |
| `applicationWillTerminate` | 解锁 → 停止看门狗线程、invalidate Timer、移除通知观察者 |
| `atexit` / SIGTERM / SIGINT | `KeyBlocker.emergencyRelease()` 兜底释放事件劫持 |

空闲时的实测占用（Apple Silicon）：

- **物理内存（footprint）约 27MB**，长时间驻留无增长
- **RunLoop 唤醒约 4 次/秒**（0.5s 状态轮询 + 看门狗心跳），不存在高频轮询

> 早期版本给解锁按钮挂了一个常驻 30Hz 计时器，导致 App 什么都不做也每秒被唤醒 30 次。
> 已改为**只在按住按钮期间**才创建计时器。

想自己复核占用，可以用随包的测量脚本（沙箱里 `ps`/`top` 常不可用，这里直接读 libproc）：

```bash
pgrep -x SafeKeys                     # 拿到 PID
scripts/proc_rss.py <PID>             # 单次快照
scripts/proc_rss.py <PID> --watch 30  # 观察 30 秒，报告内存增量与每秒唤醒次数
```

---

## 已知限制

- Touch ID 按钮和电源键无法拦截，但它们只在登录/授权弹窗里起作用，不影响清洁过程
- 触控板和鼠标不锁（安全设计，不是偷工减料）
- 本地 ad-hoc 签名：不能公证的系统更新提示、重装系统后需重新授权

---

## 卸载

一条命令，或者双击 dist 目录里的 **卸载 SafeKeys.command**：

```bash
./scripts/uninstall.sh            # 会先列出待删清单让你确认
./scripts/uninstall.sh --yes      # 跳过确认直接删
```

它会按顺序做四件事：

1. **先让运行中的实例优雅退出** —— 这一步同时保证键盘解锁，不会出现"卸载完键盘还锁着"
2. **删配置与缓存**：UserDefaults、Application Support、Caches、HTTPStorages、Saved Application State
3. **删隐私授权记录**：辅助功能 / 输入监控里的 SafeKeys 条目一并抹掉（这一步最容易被人忘，
   导致卸载几个月后系统设置里还挂着一条幽灵条目）
4. **删 App 本体**（自动查找 `/Applications`、`~/Applications`、`dist/` 三个位置，
   也可手动追加路径：`./scripts/uninstall.sh /path/to/SafeKeys.app`）

最后会逐项校验残留清单，全部清空才返回 ✅。清理路径是固定白名单，不做任何通配扫描。

**唯一需要手动的一件事**：如果你把图标拖过 Dock 或 Launchpad，把它手动拖出去即可 ——
macOS 不允许第三方脚本改动 Dock 布局。

> App 自身也带同一套清理能力，即使脚本弄丢了也能用（作为备用方案）：
> `/Applications/SafeKeys.app/Contents/MacOS/SafeKeys --uninstall`

---

## 命令行辅助

```bash
```bash
# 验证解锁口令引擎的判定是否正确（不需要任何权限，纯逻辑断言）
/Applications/SafeKeys.app/Contents/MacOS/SafeKeys --selftest

# 重置辅助功能授权（授权状态混乱时用，之后重启 app 重新勾选）
tccutil reset Accessibility cn.open-book.SafeKeys

# 查看当前设置的锁定时长（秒，0 = 不限时）
defaults read cn.open-book.SafeKeys SafeKeys.lockDurationSeconds

# 如果你的 Mac 上 Cmd+Tab 没被拦住，切到 session 层级试试（然后重启 app）
defaults write cn.open-book.SafeKeys SafeKeys.tapLocation -bool false
```

---

## 重新构建

改完代码后执行 `./scripts/build-app.sh`，会原地覆盖 `dist/SafeKeys.app`。

重新签名后 macOS 有时认不出这是同一个程序，表现为"已经勾了辅助功能但还是拦不住"。
这时重置一次授权再重新勾选即可：

```bash
tccutil reset Accessibility cn.open-book.SafeKeys
```
