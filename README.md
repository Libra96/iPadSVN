# iPadSVN

iPad 原生 SVN 客户端 — **内嵌 libsvn**，无后端。

## 功能

- Checkout / Update / Commit / Revert
- 多仓库工作副本
- 文件浏览 + 变更 Diff + 提交历史
- 账号密码存 Keychain

## 无 Mac 安装

1. GitHub **Actions** → **Build iPadSVN App**（先编 libsvn，再编 App）
2. 下载 **iPadSVN-ipa**
3. Windows **Sideloadly** 装 iPad

详见 [docs/无Mac安装指南.md](docs/无Mac安装指南.md)

## 使用

1. 打开 App → **Checkout 新仓库**
2. 填 SVN URL、用户名、密码
3. 进入仓库浏览文件、提交变更

## 结构

```
iPadSVN/           SwiftUI + libsvn 桥接
scripts/           libsvn iOS 交叉编译
vendor/            CI 产出 libsvn.xcframework
```
