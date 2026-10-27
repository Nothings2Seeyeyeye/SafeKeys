# SafeKeys — macOS 键盘清洁锁 技术方案 v1

> 目标：擦键盘时彻底锁住输入，并且**在任何情况下都保证能解锁**。
> 运行环境：macOS 15.6 Sequoia / Apple Silicon / 仅装 Xcode Command Line Tools（无 Xcode.app）

---

## 一、结论先行

| 问题 | 结论 |
|---|---|
| 用什么机制锁键盘 | `CGEventTap`，在系统 HID 层把所有键盘事件吞掉（回调返回 `nil`） |
| 能锁住 Cmd+Tab / Cmd+Q / F1–F12 吗 | 用 `kCGHIDEventTap` 可以，媒体键需额外监听 `SystemDefined`(type=14)。**必须实测验证** |
| 能锁住电源键 / Touch ID 吗 | 不能，属硬件层，无法用公开 API 拦截（方案里用别的办法规避） |
| 解锁方案 | **四主 + 三兜底**，共 7 层，任意一层触发即可解锁 |
| 最坏情况 | 进程死亡 → event tap 作为进程资源自动释放 → 键盘必然恢复。**不存在"锁死变砖"的可能** |
| 开发成本 | CLI 验证版 ~1 小时；完整菜单栏 App ~1 天 |

---

## 二、同类项目调研（GitHub）

| 项目 | 语言 | 锁的方式 | 解锁方式 | 短板 |
|---|---|---|---|---|
| [Cleankey](https://github.com/kcin1107/cleankey) | Swift | HID event tap | 菜单栏开关 | 单一解锁通道；无看门狗 |
| [LUCE](https://github.com/arinltte/LUCE) | Swift/SwiftUI | CGEvent tap | 浮动面板点击 + `atexit` 兜底 | 有亮度检查（好想法）；仍无独立看门狗 |
| [CleanKeys](https://github.com/rbayuokt/CleanKeys) | Swift | `cgSessionEventTap` + type 14 | 按钮切换 | session tap 层级较浅，Cmd+Tab 拦截存疑 |
| [keylock](https://github.com/kfv/keylock) | Swift CLI | CGEvent tap | `Ctrl+U` 组合键 | 只有键盘解锁，CLI 无 UI 兜底 |
| [shamal/keyboard-cleaner](https://github.com/shamal/keyboard-cleaner) | ObjC | event tap 全屏 | **按住右键 1 秒** | 作者自己写了 auto-kill 脚本，说明踩过坑 |

**共同点**：锁的方式完全一致（event tap）。
**共同短板**：解锁通道单薄，多数项目依赖"菜单栏 UI 还在且能响应"。shamal 那个项目甚至要用户自己跑一个 `auto-kill.sh` 保平安 —— 这正是本方案要内建解决的核心问题。

### 借鉴的点
- **LUCE 的亮度检查**：锁屏前若屏幕亮度 < 20% 就拒绝锁定。因为擦键盘时如果看不清"解锁"按钮，等于半只腿踏进坑里。→ **采纳，设为强制前置检查**
- **shamal 的 auto-kill**：超时强制杀进程。→ **采纳，升级为进程内建看门狗**
- **CleanKeys 的 type 14**：媒体键/亮度键走 `NX_SYSDEFINED`，不处理就漏。→ **采纳**

---

## 三、技术方案

### 3.1 拦截层实现要点

```swift
// 三个必须覆盖的事件类型，缺一个就漏
let mask =
    (1 << CGEventType.keyDown.rawValue)      // 按下
  | (1 << CGEventType.keyUp.rawValue)        // 抬起
  | (1 << CGEventType.flagsChanged.rawValue) // Cmd/Shift/Option/Ctrl 状态变化
  | (1 << 14)                                // NX_SYSDEFINED：亮度、音量、播放、部分 F 键

CGEvent.tapCreate(
    tap: .cgHIDEventTap,          // 关键：用 HID 层而非 Session 层，才能拦住系统快捷键
    place: .headInsertEventTap,   // 插在最前面，抢在其他 app 的 tap 之前
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: tapCallback,
    userInfo: nil
)
// 回调里 return nil  = 事件被丢弃
// 回调里 return event = 事件放行
```

**为什么用 `cgHIDEventTap` 而不是 `cgSessionEventTap`**
Session tap 插在 WindowServer 之后，`Cmd+Tab` 这类由系统 Dock 直接消费的组合键可能已经处理完了。HID tap 是最早的用户态拦截点。代价是要求辅助功能权限（两者都要，所以没有额外成本）。

**必须处理的三种异常情况**
```swift
case .tapDisabledByTimeout, .tapDisabledByUserInput:
    // macOS 检测到 tap 回调太慢会自动禁用它
    if stillWithinLockWindow { CGEvent.tapEnable(tap: tap, enable: true) }  // 维持锁定
    else { release() }                                                       // 窗口已过：安全释放
```
回调必须**极轻量**（纯指针比较 + 计数器），任何耗时操作都会导致全系统输入卡顿。

### 3.2 锁定覆盖范围

| 输入 | 是否锁定 | 说明 |
|---|---|---|
| 字母/数字/符号键 | ✅ | keyDown/keyUp |
| Cmd / Shift / Option / Ctrl / Fn | ✅ | flagsChanged |
| Cmd+Tab、Cmd+Space、Cmd+Q、Cmd+H、Cmd+Opt+Esc | ✅ | HID 层拦截（待实测确认） |
| Ctrl+Cmd+Q 锁屏 | ✅ | 同上 |
| F1–F12（亮度/音量/播放） | ✅ | SystemDefined type 14 |
| 输入法切换（中/英、候选字） | ✅ | 走 keyDown |
| 外接 USB / 蓝牙键盘 | ✅ | HID 层统一拦截 |
| 鼠标移动 / 点击 / 触控板手势 | ❌ **保留** | 这是解锁的物理保障，永不拦截 |
| 屏幕关闭 / 合盖 / Touch ID / 电源键 | ❌ | 硬件层，公开 API 无法拦截 |

> **Touch ID 的规避**：Touch ID 按钮不能被拦截，但它只在登录/授权弹窗场景有作用。本方案不用 Touch ID 作为解锁方式，避免"擦键盘时误触 Touch ID"的新问题。

---

## 四、解锁方案（核心）

设计原则：**任意单一故障都不能导致无法解锁**。四条主路径 + 三条兜底，彼此不依赖同一套代码。

### 主路径

**L1 · 面板大按钮（鼠标点一下）**
- 锁定后立即弹出顶层浮层（`NSPanel`, level = `.screenSaver`），中央一个直径 200px 的"解锁"按钮 + 倒计时圆环
- 鼠标/触控板永远可用，按钮永远在固定位置
- 菜单栏图标同步变为醒目的锁定状态色

**L2 · Esc 连按 3 次（键盘口令）**
- 在 tap 回调内部计数：1.5 秒内 3 次 Esc keydown → 立即释放 tap
- 口令写在浮层上，永远不会忘
- 可自定义为 `Cmd+Shift+U` 等组合；提供"双击 Shift"等备选
- 注意：识别逻辑只允许做整数比较，不许在回调里做任何 IO

**L3 · 倒计时自动解锁**
- 默认 90 秒，可调 30s / 60s / 120s
- **硬上限 10 分钟**：无论用户设置成多少，到点强制解锁（防止"设了 9999 秒然后忘了"）
- 浮层上有醒目倒计时，最后 10 秒变红并倒数

**L4 · 进程终止 = 解锁**
- event tap 是进程资源，**进程一死 tap 必然被内核回收**，这是 macOS 的保证
- 因此最后一保险极其简单：`pkill -x SafeKeys` 或强制退出 → 键盘恢复
- 这条写进 README 第一行

### 兜底机制

**B1 · 生命周期钩子全覆盖**
在以下所有路径都调用同一个 `emergencyUnlock()`（幂等）：
- `SIGTERM` / `SIGINT` handler
- `atexit()` 注册
- `applicationWillTerminate:`
- 浮层窗口关闭
- RunLoop 退出
> 注意不能只依赖 `deinit` —— Swift 里 `NSApplication.run()` 返回后 deinit 未必执行。必须 `atexit` 兜底。

**B2 · 进程内看门狗（关键创新点，同类项目都没有）**
主线程一旦卡死，RunLoop 停转 → tap 回调不再被调用 → **全系统键盘永久失效**，且此时 UI 无响应、点不了按钮。这是唯一真正的灾难场景。
对策：
```
独立 pthread，完全不依赖 RunLoop：
  每 500ms 检查主线程心跳计数器
  连续 3 秒（6 次）心跳无变化 → 判定主线程卡死
     → 调用 CGEvent.tapEnable(tap, false)   // 先释放 tap
     → abort()                              // 再自杀，进程资源全清
```
主线程通过一个 `volatile` 计数器在 RunLoop 每次迭代自增，看门狗只读不写，无锁无竞态。

**B3 · 权限与环境变化自动解锁**
监听并自动解锁（宁可解锁也不要卡死）：
- 辅助功能权限被取消 → tap 失效 → 解锁 + 弹提示
- 系统睡眠 / 唤醒 / 屏幕锁定 / 用户切换
- 距离上次成功解锁超过硬上限（同 L3，由看门狗线程强制执行）

### 失败场景覆盖矩阵

| 故障场景 | 生效的解锁层 | 结果 |
|---|---|---|
| 按钮点不到（屏幕太暗） | 亮度前置检查 + L2 + L3 | 不会进入该状态 |
| 面板被其他窗口盖住 | 面板 `level = .screenSaver` 置顶 | 不会盖住 |
| App 崩溃 / segfault | L4 + B1 | 进程死 → tap 释放 |
| 主线程卡死（死锁/无限循环） | **B2 看门狗** | 3 秒后自动恢复 |
| 用户误设了极长倒计时 | L3 硬上限 10 分钟 | 到点解锁 |
| 忘了怎么解锁 | L2 口令写在屏幕上 | 看得见就能解 |
| 权限被撤销 | B3 | 自动解锁并提示 |
| 拔掉外接鼠标，触控板也不灵 | L2 + L3 | 键盘口令 / 倒计时仍生效 |
| macOS 自动禁用 tap | 回调重启用 + B3 | 仍安全 |

---

## 五、UI 设计

```
┌─ 菜单栏 ────────────────────────  🔒  ─┐
│  ┌────────────────────────────────┐   │
│  │  锁定键盘      ●─────── 已就绪  │   │
│  ├────────────────────────────────┤   │
│  │  时长    30s │ 60s │ 90s │ 120s │   │
│  │  解锁口令  Esc ×3（可改）       │   │
│  │  同时锁触控板   ⃝               │   │
│  ├────────────────────────────────┤   │
│  │  自检 / 权限状态 / 关于         │   │
│  └────────────────────────────────┘   │
└───────────────────────────────────────┘

锁定态：半透明深色浮层（可调透明度 0–90%）
        ┌──────────────────────────────┐
        │        键盘已锁定              │
        │                              │
        │        ⭕ 00:47               │  ← 倒计时圆环
        │                              │
        │     [      点击解锁      ]    │  ← 200px 大按钮
        │                              │
        │   或连按 Esc 三次 · 或等待倒计时 │
        └──────────────────────────────┘
```

- 浮层默认半透明，既能看清解锁按钮，也能顺手擦屏幕
- 提供"不显示浮层（仅菜单栏）"选项给不需要擦屏的人
- 可选"顺便暗色 / 纯色背景"，顺带当屏幕脏污检查模式用

---

## 六、工程结构与构建（无 Xcode）

```
SafeKeys/
├── Package.swift                    # SwiftPM，platforms: macOS(.v13)
├── Sources/
│   └── SafeKeysApp/
│       ├── AppDelegate.swift        # 菜单栏、生命周期
│       ├── KeyBlocker.swift         # CGEventTap 拦截（唯一核心）
│       ├── Watchdog.swift           # B2 独立线程看门狗
│       ├── LockPanel.swift          # NSPanel 浮层
│       ├── Brightness.swift         # IOkit DisplayServices 亮度检查
│       ├── Permissions.swift        # AXIsProcessTrusted + 权限变更监听
│       ├── Settings.swift           # UserDefaults：时长/口令/透明度
│       └── main.swift
├── Resources/
│   ├── Info.plist                   # LSUIElement = true（不显示 Dock 图标）
│   └── Assets/                      # 菜单栏图标
├── scripts/
│   ├── build-app.sh                 # swift build -c release + 组装 .app bundle
│   └── codesign.sh                  # codesign --force --deep -s - （ad-hoc）
└── docs/
    └── PROPOSAL.md
```

**构建命令**
```bash
./scripts/build-app.sh     # 产出 dist/SafeKeys.app
open dist/SafeKeys.app     # 首次需右键 → 打开（未公证）
```

关于签名的**重要提醒**：ad-hoc 签名（`--sign -`）下，每次重新签名若 bundle identifier 变化，TCC 权限条目会失效。因此：
- bundle id 固定为 `cn.open-book.SafeKeys`，永不改
- 重签后若发现"已授权但仍失效"，执行 `tccutil reset Accessibility cn.open-book.SafeKeys` 再重新授权
- 后续若要公证，需要 Apple Developer 账号（$99/年）；自用的话 ad-hoc 足够

---

## 七、权限

| 权限 | 用途 | 对应系统设置路径 |
|---|---|---|
| 辅助功能 Accessibility | 创建 event tap 并丢弃事件 | 系统设置 → 隐私与安全性 → 辅助功能 |
| 输入监控 Input Monitoring | 接收按键事件（macOS 要求同时具备） | 系统设置 → 隐私与安全性 → 输入监控 |

> macOS 26 起这两项改名为「设备控制」和「数据访问」。你当前是 15.6，仍是旧名称。
> **授权后必须重启 App** 才生效（TCC 限制），UI 里要写清楚这一步。

首次启动流程：权限自检 → 未授权则显示引导卡 + 一键跳转系统设置 → 授权完成前 **禁用"锁定"按钮**（绝不允许出现"以为锁了其实没锁"的静默失败）。

---

## 八、验收测试清单

上线前必须逐条实测通过（我会把这些写成 `scripts/verify.md` 手动 checklist）：

**拦截有效性**
- [ ] Cmd+Tab 应用切换
- [ ] Cmd+Space Spotlight / 输入法切换
- [ ] Cmd+Q / Cmd+W / Cmd+H
- [ ] Cmd+Opt+Esc 强制退出
- [ ] Ctrl+Cmd+Q 锁屏
- [ ] F1/F2 亮度，F10-12 音量，F8 播放
- [ ] 大写锁定 Caps Lock
- [ ] 中文输入法候选中回车上屏
- [ ] 外接键盘 + 内置键盘同时
- [ ] 连续猛擦（模拟真实擦键盘的随机连击）

**解锁可靠性（重点）**
- [ ] 点按钮解锁
- [ ] Esc 连按 3 次解锁
- [ ] 倒计时到点解锁
- [ ] 硬上限强制解锁（设 9999 秒测试）
- [ ] `pkill -x SafeKeys` 后键盘恢复
- [ ] 在「活动监视器」强制退出后键盘恢复
- [ ] 主线程人为卡死 5 秒 → 看门狗触发 → 键盘自动恢复
- [ ] 系统睡眠 → 唤醒后键盘可用
- [ ] 取消辅助功能权限 → 自动解锁
- [ ] 亮度 15% 时拒绝锁定

**体验**
- [ ] 锁定期间输入无卡顿感（tap 回调耗时 < 0.1ms）
- [ ] 菜单栏图标状态一目了然
- [ ] 拔掉外接鼠标（仅剩触控板）仍能解锁

---

## 九、实施计划

| 阶段 | 内容 | 产出 | 风险 |
|---|---|---|---|
| **P0 探针**（~1h） | 一个纯 CLI 小程序：`safeky-probe --lock 30`，验证 HID tap 能否拦住 Cmd+Tab / 媒体键 | 二进制 + 实测结论 | 若 Cmd+Tab 拦不住，需降级到 session tap 并告知局限 |
| **P1 MVP**（~0.5d） | 菜单栏 App：锁定、浮层、鼠标解锁、Esc×3、倒计时、权限引导 | 可用 .app | 中 |
| **P2 加固**（~0.5d） | 看门狗线程、亮度检查、生命周期全覆盖、权限监听、硬上限 | 生产版 .app | 低 |
| **P3 打磨**（可选） | 透明度调节、外观主题、开机自启、快捷键唤起锁定 | 完整版 | 低 |

**P0 必须先做**，因为整个方案的地基是"HID tap 到底能拦住多大范围"。这一条没验证，后面 UI 做得再漂亮也没意义。

---

## 十、待你拍板的几个选择

1. **要不要同时锁触控板/鼠标？**（擦 MacBook 时触控板也会被蹭到）
   - 选是：解锁只能靠 Esc×3 + 倒计时两条路，安全感下降 → 建议仅在开启"限时 ≤ 60 秒"时允许
   - 选否：更安全，只锁键盘 ← **默认推荐**

2. **App 名字**：暂定 SafeKeys。你有偏好可以改，注意 bundle id 一旦定下就别再改（影响 TCC 权限）。

3. **是否需要开机自启 / 全局快捷键唤起**（如 Cmd+Shift+L 直接锁定）？

4. **是否需要公证**（Apple Developer 账号）：不公证则每次更新的 .app 首次打开都要右键 → 打开，且重装后要重新授权。自用无妨。
