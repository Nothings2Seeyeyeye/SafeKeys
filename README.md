# SafeKeys

清洁 Mac 时锁定键盘，抹布蹭到的按键不会触发任何操作。鼠标和触控板照常可用。

<p align="center">
  <b>锁定</b> → 擦键盘 → <b>解锁</b>，全程约 30 秒。
</p>

**English**: A small macOS utility that locks the keyboard (and only the keyboard) while you clean it.
中文文档如下。

---

## 目录

- [一分钟上手](#一分钟上手)
- [它能做什么](#它能做什么)
- [安装](#安装)
- [首次运行：授权辅助功能](#首次运行授权辅助功能)
- [使用说明](#使用说明)
- [原理](#原理)
- [卸载](#卸载)
- [从源码构建](#从源码构建)
- [常见问题](#常见问题)
- [项目结构](#项目结构)

---

## 一分钟上手

```bash
# 1. 解压后把 App 放进「应用程序」（Release 页面下载 zip）
cp -R SafeKeys.app /Applications/

# 2. 首次运行前，解除 macOS 对本地签名 App 的拦截
xattr -dr com.apple.quarantine /Applications/SafeKeys.app

# 3. 打开 → 按提示勾选「辅助功能」→ 退出重开
open /Applications/SafeKeys.app
```

之后每次使用：

1. 打开 SafeKeys，点 **锁定键盘**
2. 尽情擦拭 —— 期间任何按键都不会生效
3. 按住浮层上的 **按住解锁** 按钮 0.8 秒解锁（不按也会在倒计时结束时自动解锁）

> 记不住怎么解锁？口令就写在浮层上。**最坏情况下 `pkill -x SafeKeys` 一定能解锁。**

---

## 它能做什么

| 输入类型 | 锁定期间是否生效 |
|---|---|
| 字母数字符号、Enter、空格、Tab | ❌ 全部丢弃 |
| Cmd+Tab / Cmd+Space / Cmd+Q / Ctrl+Cmd+Q / Cmd+Opt+Esc | ❌ 全部丢弃 |
| Cmd / Shift / Option / Ctrl / CapsLock | ❌ 全部丢弃 |
| F1–F12 亮度、音量、播放控制 | ❌ 全部丢弃 |
| 中英文输入法切换与候选上屏 | ❌ 全部丢弃 |
| 外接 USB / 蓝牙键盘 | ❌ 全部丢弃 |
| **鼠标、触控板** | ✅ 保留（故意的，见下） |
| Touch ID 按钮、电源键 | ⚠️ 无法拦截（由系统硬件层面处理） |

**为什么不锁触控板**：留一条不依赖键盘的操作通道，这是安全设计。
全锁死之后一旦软件出问题就真的叫天天不应了；保留鼠标意味着你永远能用按钮解锁。

---

## 安装

### 方式一：下载编译好的 App（推荐）

从 [Releases](https://github.com/Nothings2Seeyeyeye/SafeKeys/releases) 下载
`SafeKeys-x.x.x.zip`，解压后把 `SafeKeys.app` 拖进「应用程序」。

App 是 ad-hoc 自签名、未公证，首次打开需要：

```bash
xattr -dr com.apple.quarantine /Applications/SafeKeys.app
```

若仍提示"无法验证开发者"，右键 App → 打开。

### 方式二：从源码构建

见 [从源码构建](#从源码构建)。

> ⚠️ **装到哪个位置就别再移动它**。macOS 的辅助功能授权按 App 路径记录，
> 换路径会被当成另一个程序，授权随即失效。

---

## 首次运行：授权辅助功能

这是唯一必须的一步，没有它 SafeKeys 什么都做不了。

1. 打开 App，主界面底部会显示 **需要辅助功能权限**
2. 点 **去设置** → 在系统设置里勾选 SafeKeys
3. **完全退出再重新打开 SafeKeys**（TCC 权限只在下次启动时生效）

授权成功后界面显示绿色的 **辅助功能已授权**，**锁定键盘** 按钮变为可用。

未授权时按钮是灰的 —— 这是刻意的，避免出现"以为锁了其实根本没锁"的静默失败。

**重置授权：**

```bash
tccutil reset Accessibility cn.open-book.SafeKeys
```

---

## 使用说明

### 主界面

| 区域 | 说明 |
|---|---|
| 状态灯 | 绿色 = 键盘正常，红色 = 已锁定 |
| 锁定键盘 | 普通点击即生效，仅在未锁定且已授权时可用 |
| 按住解锁 | 需按住 0.8 秒，仅锁定时可用。单击无效，防止擦洗时蹭到触控板误解锁 |
| 自动解锁 | 30 秒 / 60 秒 / 90 秒 / 2 分钟 / 不限时 |
| 解锁口令 | Esc ×4（默认）/ Tab·Esc 交替 / ⌘⌥U / 不用键盘 |

> **无论选多久，10 分钟一到强制解锁。** 这是改不掉的硬上限，防止忘了自己还在锁定状态。

### 键盘快捷键

| 快捷键 | 作用 |
|---|---|
| Cmd+Q | 退出 App（自动解锁） |
| Cmd+W | 关闭窗口（自动解锁并退出） |
| Cmd+M | 最小化 |
| Cmd+C / Cmd+V | 复制粘贴 |

点菜单栏 **SafeKeys → 关于 SafeKeys** 可查看版本信息、解锁通道速查和卸载命令入口。

### 四种解锁方式

任选其一即可：

| 方式 | 怎么用 |
|---|---|
| **按住解锁按钮 0.8 秒** | 浮层正中央，带进度条。蹭一下不会触发 |
| **解锁口令** | 默认连贯地连按 Esc 四次，口令印在浮层上 |
| **等倒计时** | 时间到自动解锁 |
| **`pkill -x SafeKeys`** | 万能钥匙，任何时候都有效 |

---

## 原理

### 拦截发生在哪一层

macOS 的按键从键盘到应用要经过好几层。SafeKeys 用 `CGEventTap` 插在 **HID 事件层** ——
用户输入抵达应用之前最早的用户态节点之一：

```
物理按键 → HID 驱动 → 【SafeKeys 的 Event Tap】→ WindowServer → 前台 App
                             ↑
                    回调返回 nil = 事件被丢弃
```

之所以必须选 HID 层（`kCGHIDEventTap`）而不是更浅的 session 层，是因为
**只有 HID 层能拦住 Cmd+Tab、Ctrl+Cmd+Q 这类系统级快捷键**，session tap 拦不住。

此外还要单独监听 `NX_SYSDEFINED`（事件类型 14）—— F1–F12 的亮度、音量、播放键
走的是这条系统自定义通道，不纳入掩码就会整组漏掉。

**Tap 只在锁定期间创建，解锁即销毁。** 不锁键盘时它完全不碰你的任何按键。

### 为什么不会被绕过

| 保障层 | 内容 |
|---|---|
| 1 | **tap 是进程资源** —— 进程一旦消亡，内核必然回收，键盘必然恢复。这是操作系统层面的保证，不是约定 |
| 2 | `atexit` + SIGINT / SIGTERM 处理函数，覆盖所有退出路径 |
| 3 | **独立看门狗线程**：主线程 3 秒无心跳，立即释放 tap 并退出。它不依赖 RunLoop，专门应对"进程活着但主线程卡死"这种唯一真正收不了场的场景 |
| 4 | 权限被撤销、系统睡眠、锁屏、用户切换 → 自动解锁 |
| 5 | 10 分钟强制解锁硬上限 |

理论上不存在锁死的可能 —— 磁盘上的 App 还在，键盘也一定还能用。

### 为什么不会误解锁

擦键盘时手指会不规则地蹭过很多键，早期版本因此容易被"误碰"解锁。现在口令要同时满足：

| 约束 | 挡住什么 |
|---|---|
| 必须是**多个**按键 | 单个键被蹭到 |
| 相邻间隔 0.1–0.8 秒 | 抹布划过去的连击 |
| 中途碰到任何其他键就重来 | 擦洗时总有好几个键一起被蹭到 |
| 按住不放的 autorepeat 不计，且直接打断序列 | 手压在某个键上不动 |
| 锁定后 2 秒冷却期 | 刚点完锁定、手还没离开键盘那一下 |

> 顺带修过一个真实缺陷：按住 Esc 不放时系统会连续上报 autorepeat 事件，
> 旧逻辑把它算成多次按下 —— 等于**压住 Esc 一下就解锁了**。现在 autorepeat 不计且会打断序列。

### 空闲时的开销

App 只在**你主动锁定**时才干活。日常打开放着时：

- 物理内存约 **27 MB**，长时间观察无增长
- RunLoop 唤醒约 **4 次/秒**（状态轮询 + 看门狗心跳）
- 关闭窗口即退出进程，不留任何后台驻留项

想自己复核可用随包脚本（某些受限环境里 `ps` / `top` 不可用，脚本直接读 libproc）：

```bash
scripts/proc_rss.py <PID>              # 单次快照
scripts/proc_rss.py <PID> --watch 30   # 观察 30 秒，报告内存增量与唤醒频率
```

---

## 卸载

**方式一：脚本（推荐）**

```bash
./scripts/uninstall.sh            # 会先列出待删清单让你确认
./scripts/uninstall.sh --yes      # 跳过确认
```

或者在 `dist/` 目录里双击 **卸载 SafeKeys.command**。

它依序完成四件事，并逐项复验：

1. 让运行中的实例优雅退出 —— 保证不会出现"卸载完键盘还锁着"
2. 删除配置与缓存：UserDefaults、Application Support、Caches、HTTPStorages、
   Saved Application State、Logs
3. 清除**隐私授权记录**（辅助功能 / 输入监控）—— 这一步最容易被人忘，
   通常卸载几个月后系统设置里还挂着一条灰掉的幽灵条目
4. 删除 App 本体，自动查找 `/Applications`、`~/Applications`、`dist/` 三个位置

清理路径是写死的白名单，**不做任何通配扫描**。

**方式二：App 自带清理**（脚本弄丢时用它）

```bash
/Applications/SafeKeys.app/Contents/MacOS/SafeKeys --uninstall
rm -rf /Applications/SafeKeys.app
```

**唯一需要手动的一步**：如果你把图标拖过 Dock 或 Launchpad，把它拖出去即可 ——
macOS 不允许第三方脚本改动 Dock 布局。

> `tccutil` 清除授权时若返回 `Operation not permitted`，给终端授予
> 「完全磁盘访问权限」后重跑一次。脚本会如实报告清除失败，不会假装成功。

---

## 从源码构建

### 环境要求

- macOS 13+
- **仅需 Xcode Command Line Tools**（无需完整 Xcode）

```bash
xcode-select --install
```

### 构建

```bash
git clone https://github.com/Nothings2Seeyeyeye/SafeKeys.git
cd SafeKeys
./scripts/build-app.sh
```

产物在 `dist/SafeKeys.app`。若要重新分发 zip：

```bash
ditto -c -k --keepParent dist/SafeKeys.app dist/SafeKeys.zip
```

### 自检

```bash
dist/SafeKeys.app/Contents/MacOS/SafeKeys --selftest
```

21 条纯逻辑断言，覆盖四种口令模式、间隔边界、autorepeat、冷却期、修饰键打断，
以及菜单栏完整性（Cmd+Q / Cmd+W 绑定、应用菜单标题、「关于」项是否存在）——
不依赖任何系统权限，可放进 CI。

### 重新生成图标

```bash
# 1. AI 生成 1024×1024 源图后抠掉白底（生成模型的「透明背景」常常是假的纯白）
scripts/remove_white_bg.py <源图.png> icon_transparent.png

# 2. 按 macOS 网格规范排版：大尺寸图形占画布 80.5%，小尺寸 90%
scripts/make-iconset.py icon_transparent.png AppIcon.iconset

# 3. 合成 icns
iconutil -c icns AppIcon.iconset -o Resources/icon/AppIcon.icns
```

---

## 常见问题

| 问题 | 解决 |
|---|---|
| **Cmd+Q 没反应** | v1.1.3 之前的版本缺少主菜单栏。更新到最新版 |
| 提示"无法验证开发者" | `xattr -dr com.apple.quarantine /Applications/SafeKeys.app` |
| 授权了但按钮仍不可用 | **完全退出再重开**（TCC 权限下次启动才生效） |
| 移动 App 后授权失效 | App 不要移动；重装后重新勾选即可 |
| 锁定按钮是灰的 | 尚无辅助功能权限，见[授权一节](#首次运行授权辅助功能) |
| Cmd+Tab 没被拦住 | 试切到 session tap：`defaults write cn.open-book.SafeKeys SafeKeys.tapLocation -bool false` |
| 忘了怎么解锁 | 口令印在浮层上；或者 `pkill -x SafeKeys` |
| 浮层挡住解锁按钮 | 浮层层级高于所有窗口，不会被盖住；此时用口令或 `pkill` |
| App 卡死不动 | 看门狗 3 秒后自行释放并退出；也可直接 `pkill -x SafeKeys` |

### 已知限制

- Touch ID 与电源键无法拦截，但它们只在登录/授权弹窗中起作用
- 触控板和鼠标不锁（安全设计）
- ad-hoc 自签名：不能公证的系统更新提示，重装系统后需重新授权

---

## 项目结构

```
SafeKeys/
├── Package.swift                  # SwiftPM 清单（无 Xcode 工程）
├── Resources/
│   ├── Info.plist
│   └── icon/                      # 图标源图与 icns
├── Sources/SafeKeys/
│   ├── main.swift                 # 入口、atexit 与信号处理兜底
│   ├── Menus.swift                # 主菜单栏（Cmd+Q 等快捷键的绑定来源）
│   ├── AboutPanel.swift           # 「关于」面板
│   ├── AppDelegate.swift          # 窗口生命周期、关窗即退出
│   ├── KeyBlocker.swift           # CGEventTap 安装/释放、事件分类
│   ├── UnlockPhraseMatcher.swift  # 口令判定（纯逻辑，可自检）
│   ├── LockManager.swift          # 锁定/解锁状态机
│   ├── OverlayWindow.swift        # 全屏浮层
│   ├── HoldToUnlockButton.swift   # 按住才生效的解锁按钮
│   ├── Watchdog.swift             # 主线程心跳监护
│   ├── Permissions.swift          # 辅助功能权限查询
│   ├── Selftest.swift             # 命令行自检
│   ├── Settings.swift             # 用户偏好与口令定义
│   └── Uninstaller.swift          # 自我清理
├── scripts/
│   ├── build-app.sh               # 编译 + 组装 bundle + ad-hoc 签名
│   ├── uninstall.sh               # 彻底卸载
│   ├── remove_white_bg.py         # 图标去白底
│   ├── make-iconset.py            # 图标排版
│   └── proc_rss.py                # 进程内存/唤醒测量
└── docs/PROPOSAL.md               # 设计调研与方案
```

---

## 许可

MIT License。自签名未公证，仅供自用。
