# Alipay2NFC

让支付宝「碰一碰」唤起你指定的第二个支付宝客户端。

Redirect Alipay's 碰一碰 (NFC tap-to-pay) to the Alipay client of your choice.

<p align="center"><b>中文</b> · <a href="#english">English</a></p>

---

## 解决的问题

在越狱设备上用 Crane 之类的工具多开支付宝之后，贴商户的碰一碰贴纸时，系统始终唤起**官方**客户端，第二个账号用不上 NFC 付款。

原因是碰一碰贴纸里是一条指向 `render.alipay.com` 的链接，iOS 按 Universal Link / App Clip 规则投递，而只有官方客户端在该域名下完成过关联声明 —— 多开客户端不在其中，系统不会把链接交给它。

## 做什么

本插件在官方客户端处理这次碰一碰的那一刻接管过来，把付款交给你的多开客户端完成：

```
贴碰一碰贴纸 → 官方客户端收到链接 → 插件接管 → 多开客户端进入碰一碰付款页
```

## 使用

1. 安装后打开官方支付宝
2. 贴商户的碰一碰贴纸 → 自动进入多开客户端的碰一碰付款页

多开客户端会被自动识别并唤起，**无需提前打开它**。

## 设置

安装后在 **设置 → 碰一碰重定向** 里：

| 选项 | 作用 |
|---|---|
| **启用碰一碰重定向** | 总开关。**想用官方账号付款时直接关掉即可**，不用卸载插件，也不用去 Choicy 里屏蔽 |
| **跳转前询问** | 每次贴纸先弹窗，当场选「跳转到多开客户端」还是「用官方支付宝支付」 |
| **目标多开支付宝** | 检测到多个多开客户端时，选择要跳转的那个；未选择时用第一个 |

改动**即时生效**，不需要注销或重启。

## 安装

**从源安装（推荐）**

在 Sileo / Zebra 中添加 `https://apt.mjh.im`，搜索 `Alipay2NFC`。

**手动安装**

从 [Releases](../../releases) 下载与你越狱类型对应的包：

| 文件 | 适用 |
|---|---|
| `..._iphoneos-arm64.deb` | rootless（Dopamine、palera1n 等） |
| `..._iphoneos-arm64e.deb` | roothide |

```bash
dpkg -i im.mjh.alipay2nfc_3.4.0_iphoneos-arm64e.deb
```

## 兼容性

| 项 | 支持 |
|---|---|
| 越狱 | rootful、rootless、roothide |
| 架构 | arm64、arm64e |
| 系统 | iOS 14 及以上 |
| 多开客户端 | 任意多开工具生成的客户端 |

## 已知限制

冷启动贴纸时，官方客户端会先生效再转交，因此会短暂出现一下。

## 构建

需要 [Theos](https://theos.dev)。

```bash
# rootless
make package THEOS_PACKAGE_SCHEME=rootless \
     SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk

# roothide（需要 roothide 版 Theos）
make package THEOS_PACKAGE_SCHEME=roothide \
     SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk
```

两点注意：

- **必须显式指定 `SYSROOT`**：设置面板依赖私有框架 `Preferences`，系统 Xcode 的 SDK 里没有，会报 `framework 'Preferences' not found`
- **路径不要含非 ASCII 字符**（中文等），GNU make 处理不了

## 结构

```
tweak/      插件本体（钩子 + 配置读取 + 热更新）
prefs/      设置面板（PreferenceBundle）
dist/       已构建的 deb
```

## 许可

[MIT](LICENSE)

---

<a name="english"></a>
# English

Redirect Alipay's 碰一碰 (NFC tap-to-pay) to the Alipay client of your choice.

## The problem

After duplicating Alipay on a jailbroken device with tools like Crane, tapping a merchant's
碰一碰 sticker always launches the **official** client — the second account can't use NFC payment.

The sticker carries a link to `render.alipay.com`. iOS delivers it as a Universal Link / App Clip,
and only the official client has an association claim for that domain, so iOS never hands the link
to the clone.

## What it does

The tweak takes over at the moment the official client processes the tap and hands the payment to
your chosen client:

```
Tap sticker → official client receives link → tweak takes over → your client opens the tap-to-pay page
```

## Usage

1. Install, then open the official Alipay
2. Tap the merchant's 碰一碰 sticker → your second client opens its tap-to-pay page

The second client is discovered and launched automatically — **you never need to open it first**.

## Settings

Under **Settings → 碰一碰重定向** (Alipay2NFC):

| Option | Effect |
|---|---|
| **Enable redirection** | Master switch. **Turn it off to pay with your official account** — no need to uninstall or block the tweak in Choicy |
| **Ask before jumping** | Show a dialog on every tap to choose between your second client and the official app |
| **Target client** | Pick which clone to use when several exist; defaults to the first |

Changes take effect **immediately** — no respring or reboot.

## Install

**Via repo (recommended)** — add `https://apt.mjh.im` in Sileo / Zebra and search for `Alipay2NFC`.

**Manual** — download the package matching your jailbreak type from [Releases](../../releases):

| File | For |
|---|---|
| `..._iphoneos-arm64.deb` | rootless (Dopamine, palera1n) |
| `..._iphoneos-arm64e.deb` | roothide |

```bash
dpkg -i im.mjh.alipay2nfc_3.4.0_iphoneos-arm64e.deb
```

## Compatibility

| Item | Support |
|---|---|
| Jailbreak | rootful, rootless, roothide |
| Architecture | arm64, arm64e |
| iOS | 14.0+ |
| Second client | Any created by any multi-instance tool |

## Known limitation

On a cold launch the official client briefly takes effect before handing over, so it appears for a
moment.

## Building

Requires [Theos](https://theos.dev).

```bash
# rootless
make package THEOS_PACKAGE_SCHEME=rootless \
     SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk

# roothide (needs a roothide-flavoured Theos)
make package THEOS_PACKAGE_SCHEME=roothide \
     SYSROOT=$THEOS/sdks/iPhoneOS16.5.sdk
```

Two notes:

- **`SYSROOT` is required**: the settings panel links the private `Preferences` framework, which the
  stock Xcode SDK lacks (otherwise: `framework 'Preferences' not found`)
- **Keep the checkout path ASCII-only** — GNU make cannot handle non-ASCII paths

## License

[MIT](LICENSE)
