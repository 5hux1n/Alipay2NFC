# Alipay2NFC

把支付宝「碰一碰」的 NFC 唤起重定向到你自己的**第二个支付宝（多开客户端）**。

Redirect Alipay's "碰一碰" (NFC tap-to-pay) to your own **second / multi-instance Alipay client**.

<p align="center">
  <b>中文</b> · <a href="#english">English</a>
</p>

---

## 这是什么

你在越狱设备上用 Crane 之类的工具多开了一个支付宝（「支付宝2」），
但贴商户的碰一碰贴纸时，iOS 永远只唤起**官方**那个 —— 因为只有官方支付宝通过了
`render.alipay.com` 的 AASA 校验。多开包的 bundle id 不在列表里，系统根本不会把 URL 投给它。

本插件让官方支付宝在收到碰一碰 URL 的那一刻，**把这次碰一碰转交给你的多开客户端**。

## 效果

```
贴碰一碰贴纸 → 官方支付宝收到 URL → 插件拦截 → 拉起「支付宝2」并进入碰一碰付款页
```

- 不需要修改任何 App 的 `Info.plist`
- 不需要重新签名多开包
- 不需要任何前置操作，装完即用

## 兼容性

| 项 | 支持 |
|---|---|
| 越狱 | rootful / rootless（Dopamine、palera1n）/ roothide |
| 架构 | arm64、arm64e |
| 系统 | iOS 14 及以上（碰一碰本身要求） |
| 多开工具 | 任意 —— bundle id 在运行时自动发现，无需配置 |
| 依赖 | 无（纯 `libobjc`，不含 CydiaSubstrate） |

## 安装

**从源安装（推荐）**

在 Sileo / Zebra 中添加源：

```
https://apt.mjh.im
```

搜索 `Alipay2NFC` 安装。

**手动安装**

从 [Releases](../../releases) 下载对应你越狱类型的 deb：

| 文件 | 适用 |
|---|---|
| `..._iphoneos-arm64.deb` | rootless（Dopamine / palera1n 等） |
| `..._iphoneos-arm64e.deb` | roothide |

```bash
dpkg -i im.mjh.alipay2nfc_3.1.0_iphoneos-arm64e.deb
```

装完打开官方支付宝，贴碰一碰贴纸即可。

## 原理

碰一碰贴纸的 NDEF 里是一条 `https://render.alipay.com/p/s/ulink/sn?...` 链接，
iOS 把它当 Universal Link / App Clip 解析。官方支付宝的 entitlements 里有
`appclips:render.alipay.com` 与 `applinks:render.alipay.com`，所以它是唯一的合法接收方。

插件在官方支付宝进程里挂两个方法（实测碰一碰的 URL 只经 `NSUserActivity` 传递）：

| 时机 | 方法 |
|---|---|
| 系统写入 URL（热启动） | `-[NSUserActivity setWebpageURL:]` |
| App 读取 URL（冷启动） | `-[NSUserActivity webpageURL]` |

命中碰一碰链接后：把原始 URL 加标记写进 `UIPasteboard`，再用
`openApplicationWithBundleID:` 拉起多开包。多开包侧的插件读到剪贴板后，
构造一个 `NSUserActivity` 投递给自己的 `continueUserActivity` —— 完全复刻 iOS 的投递方式。

多开包的 bundle id 通过 `enumerateApplicationsOfType:block:` 枚举得到
（这走 XPC 到 `lsd`，是沙盒 App 内唯一可用的枚举方式；`allInstalledApplications`
和 `allApplications` 在沙盒里都返回 0）。

## 已知限制

**冷启动贴纸时，官方支付宝会先闪一下。** 原因是 iOS 只认官方包，必须先把 URL 交给它，
插件才有机会转发 —— 这发生在 App 层之后。

要彻底消除必须在系统服务 `clipserviced` 里改道。实测该方向可以成功抑制 App Clip 卡片、
让官方不启动，但**拦下后无法把 URL 传给多开包**：守护进程既写不进 App 容器（沙盒拒绝），
也无法让 App 读到外部 preferences domain。且卡片被抑制后官方不启动，原本可靠的 App 层
转发路径也不执行，净效果更差，故未采用。

## 从源码构建

需要 [Theos](https://theos.dev)。

```bash
cd tweak

# rootless
make package THEOS_PACKAGE_SCHEME=rootless

# roothide（需要 roothide 版 Theos）
make package THEOS_PACKAGE_SCHEME=roothide
```

## 许可

[MIT](LICENSE)

---

<a name="english"></a>
# English

Redirect Alipay's **碰一碰** (tap-to-pay NFC) trigger to your own **second / multi-instance Alipay client**.

## What it does

On a jailbroken device you may run a duplicated Alipay ("支付宝2") created with tools like Crane.
But when you tap a merchant's NFC sticker, iOS always launches the **official** Alipay — because
only the official app passes the AASA check for `render.alipay.com`. The clone's bundle ID is not
in the AASA list, so iOS never delivers the URL to it.

This tweak makes the official Alipay hand the tap over to your clone the moment it receives the URL.

```
Tap NFC sticker → official Alipay receives URL → tweak intercepts → launches "支付宝2" into the tap-to-pay page
```

- No `Info.plist` modification
- No re-signing of the clone
- No setup steps — works right after install

## Compatibility

| Item | Supported |
|---|---|
| Jailbreak | rootful / rootless (Dopamine, palera1n) / roothide |
| Architecture | arm64, arm64e |
| iOS | 14.0+ (required by tap-to-pay itself) |
| Multi-instance tool | Any — the clone's bundle ID is discovered at runtime |
| Dependencies | None (pure `libobjc`, no CydiaSubstrate) |

## Install

**Via repo (recommended)** — add `https://apt.mjh.im` in Sileo / Zebra and install `Alipay2NFC`.

**Manual** — grab the deb for your jailbreak type from [Releases](../../releases):

| File | For |
|---|---|
| `..._iphoneos-arm64.deb` | rootless (Dopamine / palera1n) |
| `..._iphoneos-arm64e.deb` | roothide |

```bash
dpkg -i im.mjh.alipay2nfc_3.1.0_iphoneos-arm64e.deb
```

Then open the official Alipay and tap the sticker.

## How it works

The sticker's NDEF payload is a `https://render.alipay.com/p/s/ulink/sn?...` link, which iOS
resolves as a Universal Link / App Clip. The official Alipay has
`appclips:render.alipay.com` and `applinks:render.alipay.com` in its entitlements, making it the
only eligible recipient.

The tweak hooks two methods inside the official app (the tap URL was measured to travel **only**
through `NSUserActivity`):

| When | Method |
|---|---|
| System writes the URL (warm launch) | `-[NSUserActivity setWebpageURL:]` |
| App reads the URL (cold launch) | `-[NSUserActivity webpageURL]` |

On a match it writes the raw URL (with a marker) to `UIPasteboard` and launches the clone via
`openApplicationWithBundleID:`. The clone's side of the tweak reads the pasteboard, builds an
`NSUserActivity` and delivers it to its own `continueUserActivity` — exactly mirroring how iOS
would have done it.

The clone's bundle ID is obtained through `enumerateApplicationsOfType:block:` (an XPC call to
`lsd` — the only enumeration API that works inside a sandboxed app; both `allInstalledApplications`
and `allApplications` return 0 there).

## Known limitation

**On a cold launch the official Alipay briefly appears first.** iOS only recognises the official
app, so the URL must be delivered to it before the tweak can forward it — this happens after the
app layer.

Eliminating it would require intercepting in the system service `clipserviced`. That was tried:
it does successfully suppress the App Clip card and prevents the official app from launching, but
**the URL cannot then be handed to the clone** — a sandboxed daemon cannot write into another app's
container, and a sandboxed app cannot read another domain's preferences. Worse, suppressing the card
also prevents the working app-layer path from running at all, so that approach was dropped.

## Building from source

Requires [Theos](https://theos.dev).

```bash
cd tweak

# rootless
make package THEOS_PACKAGE_SCHEME=rootless

# roothide (needs a roothide-flavoured Theos)
make package THEOS_PACKAGE_SCHEME=roothide
```

## License

[MIT](LICENSE)
