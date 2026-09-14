# iPadSVN App v0.1 — 安装与运行

## 这版有什么

- **SwiftUI 原生 iPad App**（Timeline 浅色命令台 UI）
- **多仓库**、**文件浏览**、**变更 Diff**、**提交**、**历史**
- 当前 SVN 操作为 **Mock 演示数据**（3 个示例仓库）
- `LibSvnClient.swift` 已预留，libsvn 编过后可替换接入

## 有 Mac 时（Xcode）

```bash
cd iPadSVN
open iPadSVN.xcodeproj
```

1. 选 **iPad** 模拟器或真机
2. `Signing & Capabilities` 里填你的 **Team**
3. `Cmd + R` 运行

## 无 Mac（GitHub Actions 云编译）

1. 推送代码到 GitHub
2. **Actions** → **Build iPadSVN App** → **Run workflow**
3. 绿色 ✓ 表示 Simulator 编译通过

> 产出 `.ipa` 仍需在 Xcode 里 Archive + 导出，或使用已配置签名的 CI。v0.1 先验证能编过。

## 侧载到 iPad（Sideloadly）

1. Mac 上 Archive 导出 **Development IPA**
2. Windows 打开 [Sideloadly](https://sideloadly.io/)
3. 连接 iPad，选 IPA，填 Apple ID
4. 安装后在 iPad **设置 → 通用 → VPN与设备管理** 信任开发者

## 项目结构

```
iPadSVN/
├── iPadSVN.xcodeproj
└── iPadSVN/
    ├── App/AppStore.swift          # 状态管理
    ├── Models/SVNModels.swift
    ├── Services/
    │   ├── SVNClient.swift         # 协议
    │   ├── MockSVNClient.swift     # 当前使用
    │   └── LibSvnClient.swift      # libsvn 占位
    └── Views/                      # UI
```

## 下一步：接入真实 SVN

1. 跑通 **Verify libsvn iOS Build** 拿到 `libsvn.xcframework`
2. 在 Xcode 拖入 xcframework
3. 实现 `LibSvnClient` + C 桥接
4. `AppStore` 初始化时改用 `LibSvnClient()`
