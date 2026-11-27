# Install OfferFlow

[English](#install-offerflow) · [简体中文](#安装-offerflow)

## Build and package

On macOS 14 or later, install the Xcode Command Line Tools with `xcode-select --install` if needed. Run these commands from the repository root:

```sh
zsh scripts/build.sh
open build/OfferFlow.app
```

To create a DMG and ZIP for the build machine's architecture, run:

```sh
zsh scripts/package.sh
(cd dist && shasum -a 256 -c SHA256SUMS.txt)
```

## Install a package

Quit any running copy of OfferFlow. Open the DMG and drag `OfferFlow.app` into Applications, or extract the ZIP and move the app there. The build uses ad hoc signing and is intended for local development. Installing a distribution package on another Mac may require a Developer ID signature and Apple notarization.

---

# 安装 OfferFlow

[English](#install-offerflow) · [简体中文](#安装-offerflow)

## 构建与打包

需要 macOS 14 或更新版本。如果尚未安装 Xcode 命令行工具，请运行 `xcode-select --install`。在仓库根目录执行：

```sh
zsh scripts/build.sh
open build/OfferFlow.app
```

如需生成适用于构建机架构的 DMG 和 ZIP，请执行：

```sh
zsh scripts/package.sh
(cd dist && shasum -a 256 -c SHA256SUMS.txt)
```

## 从安装包安装

先退出正在运行的 OfferFlow。打开 DMG，将 `OfferFlow.app` 拖入「应用程序」。使用 ZIP 时，先解压，再将应用移入「应用程序」。构建产物使用临时签名，适用于本机开发。在其他 Mac 上安装分发包时，可能需要 Developer ID 签名及 Apple 公证。
