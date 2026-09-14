# iPadSVN

iPad 原生 SVN 客户端 — 无后端，计划内嵌 libsvn。

## 当前进度

| 模块 | 状态 |
|------|------|
| SwiftUI App v0.1 | ✅ Timeline 浅色 UI + Mock SVN |
| libsvn iOS 交叉编译脚本 | ✅ 待 CI 验证 |
| libsvn 接入 | ⏳ 占位 `LibSvnClient` |

## 快速开始（无 Mac）

👉 **完整步骤见 [docs/无Mac安装指南.md](docs/无Mac安装指南.md)**

简要流程：

1. 代码推到 GitHub
2. **Actions** → **Build iPadSVN App** → 下载 IPA
3. Windows 用 **Sideloadly** 装到 iPad

### 有 Mac 时

```bash
open iPadSVN/iPadSVN.xcodeproj
```

### 验证 libsvn 能否编进 iOS

GitHub → **Actions** → **Verify libsvn iOS Build**

详见 [docs/云编译步骤.md](docs/云编译步骤.md)

## 目录

```
iPadSVN/              SwiftUI 工程
design/               UI 原型 HTML
scripts/              libsvn 编译脚本
docs/                 文档
.github/workflows/    CI
```

## UI 原型

交互参考：`design/timeline-light-demo.html`
