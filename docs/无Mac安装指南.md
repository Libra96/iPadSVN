# 无 Mac 安装 iPadSVN（Windows + GitHub + Sideloadly）

你没有 Mac 也没关系：**GitHub 云 Mac 帮你编译**，Windows 上 **Sideloadly 装到 iPad**。

---

## 你需要准备

| 物品 | 说明 |
|------|------|
| GitHub 账号 | 免费即可 |
| Windows 电脑 | 你现在这台 |
| iPad + 数据线 | 安装时用 |
| Apple ID | 免费账号即可（Sideloadly 签名用） |
| [Sideloadly](https://sideloadly.io/) | Windows 版，免费 |

> 不需要 Mac，不需要付费开发者账号（$99/年）。

---

## 第一步：把代码推到 GitHub

在 PowerShell 里执行（**把 `你的用户名` 换成你的 GitHub 用户名**）：

```powershell
cd D:\MY\Code\IPAD

git add .
git commit -m "Add iPadSVN app v0.1"

# 先在 github.com 网页新建空仓库，名字例如 iPadSVN，不要勾选 README
git remote add origin https://github.com/你的用户名/iPadSVN.git
git branch -M main
git push -u origin main
```

如果提示登录 GitHub，按网页指引用 **Personal Access Token** 作为密码。

---

## 第二步：云编译出 IPA

1. 打开 GitHub 仓库页面
2. 点顶栏 **Actions**
3. 左侧选 **Build iPadSVN App**
4. 点 **Run workflow** → 绿色 **Run workflow**
5. 等约 **3～8 分钟**，出现绿色 ✓

---

## 第三步：下载 IPA

1. 点进刚才成功的那次 workflow
2. 页面最下方 **Artifacts**
3. 下载 **iPadSVN-ipa**（zip 里有个 `iPadSVN.ipa`）

---

## 第四步：Sideloadly 装到 iPad

1. 安装并打开 **Sideloadly**（Windows）
2. iPad 用数据线连电脑，iPad 上点 **信任此电脑**
3. Sideloadly 里：
   - **IPA File**：选刚下载的 `iPadSVN.ipa`
   - **Apple Account**：填你的 Apple ID
4. 点 **Start**，按提示在网页登录 / 输入验证码
5. 等待安装完成

---

## 第五步：iPad 上信任开发者

第一次打开 App 若提示「未受信任开发者」：

**设置 → 通用 → VPN 与设备管理 → 你的 Apple ID → 信任**

然后桌面打开 **iPadSVN**。

---

## 常见问题

### Q：免费 Apple ID 装的应用会过期吗？
会。免费签名一般 **7 天** 后需重新用 Sideloadly 装一次（数据一般还在）。

### Q：编译失败怎么办？
1. Actions 里点红色 ✗ 的任务
2. 展开 **Build for iOS device** 看日志
3. 把**最后 30 行**发给我

### Q：能连真 SVN 吗？
当前 v0.1 是 **Mock 演示数据**（UI 和流程完整）。真 SVN 要等 libsvn iOS 编译验证通过后接入。

### Q：推送代码后 Actions 没自动跑？
确认推送到了 `main` 分支，且改动了 `iPadSVN/` 目录；或手动 **Run workflow**。

---

## 流程图

```
Windows 写代码 / 改代码
        ↓ git push
GitHub Actions（云 Mac 编译）
        ↓ 下载 IPA
Sideloadly（Windows 签名 + 安装）
        ↓
iPad 上使用 iPadSVN
```

---

## 相关文档

- [App 功能说明](App安装步骤.md)
- [libsvn 云编译验证](云编译步骤.md)
