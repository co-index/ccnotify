<div align="center">

<img src="assets/icon.png" width="128" alt="ccnotify icon" />

# ccnotify

**Clickable macOS notifications from the command line.**

A tiny, modern replacement for `terminal-notifier`, built on
`UNUserNotificationCenter` — about 150 lines of Swift, no dependencies.

[English](#english) · [中文](#中文)

</div>

---

## English

### Why

[terminal-notifier](https://github.com/julienXX/terminal-notifier) pioneered
command-line notifications on macOS, but it has been unmaintained since 2018
and uses the deprecated `NSUserNotification` API. ccnotify keeps its
command-line interface and its clever app-bundle architecture, reimplemented
from scratch on the modern `UNUserNotificationCenter` API.

The headline feature: **clicking a notification focuses the app you choose** —
pass `-activate` with a bundle id and the click jumps you back to your
terminal, editor, or anything else.

### Install

```sh
brew install co-index/tap/ccnotify
```

Or from source (requires the Xcode Command Line Tools):

```sh
git clone https://github.com/co-index/ccnotify.git
cd ccnotify
sudo make install            # PREFIX=/usr/local by default
```

The first notification triggers a macOS permission prompt; allow **ccnotify**
under System Settings → Notifications if banners do not appear.

### Usage

```sh
ccnotify -message "Build finished"
ccnotify -title "CI" -subtitle "main" -message "All tests passed" -sound Glass
ccnotify -message "Click me" -activate com.microsoft.VSCode
```

| Flag        | Meaning                                                        |
| ----------- | -------------------------------------------------------------- |
| `-message`  | Notification body (required)                                   |
| `-title`    | Notification title (default: `ccnotify`)                       |
| `-subtitle` | Notification subtitle                                          |
| `-sound`    | Sound name from `/System/Library/Sounds` (e.g. `Glass`, `Ping`)|
| `-activate` | Bundle id of the app to focus when the notification is clicked |
| `-version`  | Print the version                                              |
| `-help`     | Show help                                                      |

Find an app's bundle id with:

```sh
osascript -e 'id of app "Visual Studio Code"'
```

### Use with Claude Code

ccnotify was born as the notifier behind a Claude Code hook setup: get a
banner when Claude finishes a task or needs your attention, click it, and
land back in the exact app that was running Claude Code. The ready-made
hook ships as a Claude Code plugin — see
[co-index/claude-plugins](https://github.com/co-index/claude-plugins).

### How it works

`ccnotify` is a shim that executes the binary inside `ccnotify.app`. Posting
runs the app for a fraction of a second; when you later click the
notification, macOS relaunches the app in the background, which reads the
target bundle id from the notification payload and activates that app. The
same architecture terminal-notifier uses — which is why a plain CLI binary
cannot do this, and an app bundle can.

Because the formula builds from source on your machine, no Apple Developer
certificate or notarization is involved; the app is ad-hoc signed locally.

### License

[MIT](LICENSE). Not affiliated with Apple or with
[terminal-notifier](https://github.com/julienXX/terminal-notifier), whose
interface design this project gratefully follows.

---

## 中文

### 为什么做这个

[terminal-notifier](https://github.com/julienXX/terminal-notifier) 开创了
macOS 命令行通知，但它自 2018 年起停止维护，使用的 `NSUserNotification`
API 也早已废弃。ccnotify 保留了它的命令行接口和 app 壳架构，用现代的
`UNUserNotificationCenter` API 从零重新实现，约 150 行 Swift，零依赖。

核心特性：**点击通知可以聚焦你指定的应用**——通过 `-activate` 传入
bundle id，点击横幅即可跳回你的终端、编辑器或任何应用。

### 安装

```sh
brew install co-index/tap/ccnotify
```

或从源码安装（需要 Xcode Command Line Tools）：

```sh
git clone https://github.com/co-index/ccnotify.git
cd ccnotify
sudo make install            # 默认 PREFIX=/usr/local
```

首次发送通知会弹出系统授权提示；如果看不到横幅，请在
系统设置 → 通知 中允许 **ccnotify**。

### 用法

```sh
ccnotify -message "构建完成"
ccnotify -title "CI" -subtitle "main" -message "测试全部通过" -sound Glass
ccnotify -message "点我跳回 VS Code" -activate com.microsoft.VSCode
```

参数含义见上方英文表格。查询应用 bundle id：

```sh
osascript -e 'id of app "Visual Studio Code"'
```

### 搭配 Claude Code

ccnotify 最初就是为 Claude Code 的通知 hook 而生：Claude 完成任务或需要
你时弹出横幅，点击即可跳回运行 Claude Code 的那个应用。现成的 hook 已
打包为 Claude Code 插件，见
[co-index/claude-plugins](https://github.com/co-index/claude-plugins)。

### 工作原理

`ccnotify` 命令是一个薄壳，实际执行 `ccnotify.app` 里的二进制。发送通知
时 app 只运行零点几秒；之后你点击通知，macOS 会在后台重新拉起这个 app，
它从通知负载中读取目标 bundle id 并激活对应应用。这正是 terminal-notifier
的架构——纯 CLI 二进制做不到这件事，app 壳可以。

brew formula 在你本机从源码编译，因此不涉及 Apple 开发者证书或公证，
应用使用本地 ad-hoc 签名。

### 许可

[MIT](LICENSE)。本项目与 Apple、
[terminal-notifier](https://github.com/julienXX/terminal-notifier) 均无关联，
并诚挚感谢后者的接口设计。
