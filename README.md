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

1. 从下方任一方式安装
2. 打开官方支付宝
3. 贴商户的碰一碰贴纸

多开客户端会在后台由插件唤起，无需提前打开它，也不用做任何配置。

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
dpkg -i im.mjh.alipay2nfc_3.1.0_iphoneos-arm64e.deb
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

1. Install by either method below
2. Open the official Alipay
3. Tap the merchant's 碰一碰 sticker

The second client is brought up in the background by the tweak — no need to open it first, and no
configuration is required.

## Install

**Via repo (recommended)** — add `https://apt.mjh.im` in Sileo / Zebra and search for `Alipay2NFC`.

**Manual** — download the package matching your jailbreak type from [Releases](../../releases):

| File | For |
|---|---|
| `..._iphoneos-arm64.deb` | rootless (Dopamine, palera1n) |
| `..._iphoneos-arm64e.deb` | roothide |

```bash
dpkg -i im.mjh.alipay2nfc_3.1.0_iphoneos-arm64e.deb
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
cd tweak

# rootless
make package THEOS_PACKAGE_SCHEME=rootless

# roothide (needs a roothide-flavoured Theos)
make package THEOS_PACKAGE_SCHEME=roothide
```

## License

[MIT](LICENSE)
