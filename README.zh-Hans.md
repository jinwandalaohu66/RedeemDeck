# RedeemDeck

[English](README.md) | [简体中文](README.zh-Hans.md)

RedeemDeck 是一款面向 Apple 开发者的原生、私密兑换码管理 App。它将 App Store Connect 导出的 CSV 整理为清晰的兑换码库存，并把日常工作聚焦在一件事上：快速取出正确数量的兑换码并发送出去。

## 主要功能

- 导入 App Store 优惠码和促销码 CSV 文件。
- 按兑换码分类区分订阅、折扣、活动和其他产品。
- 指定取码数量，并优先使用较早过期的库存。
- 复制兑换码或兑换链接、使用系统分享、保存二维码海报。
- 生成包含 App 图标、到期信息和可编辑祝福语的紧凑海报。
- 保留未完成的取码记录，避免误把待发送兑换码放回库存。
- 在独立的管理流程中搜索、筛选、编辑、归档和恢复兑换码。
- 设置本地到期提醒。
- 导出完整备份，并在恢复时安全合并数据。
- 在 iPhone、iPad 和 Mac 上使用英文或简体中文界面。

## 使用流程

1. 添加一个 App，或导入 App Store Connect 导出的 CSV。
2. 将兑换码分配到订阅、首发优惠或折扣等分类。
3. 点击“获取”，输入数量，然后进入准备好的结果页面。
4. 只对真正完成复制、分享或保存的兑换码记录发送状态。

RedeemDeck 只使用四种有效状态：

| 状态 | 含义 |
| --- | --- |
| 可用 | 兑换码仍在库存中。 |
| 待发送 | 兑换码已经取出，但尚未完成输出。 |
| 已发送 | 复制、完成系统分享或成功保存海报后，兑换码离开本地可用库存。 |
| 已过期 | 兑换码已经超过到期时间。 |

**已发送不等于已兑换。** Apple 没有提供可以匿名、稳定确认单个兑换码真实兑换状态的公开接口。RedeemDeck 不会通过反复访问兑换链接来猜测结果，也不要求用户导入 App Store Connect API Key。

## 隐私与存储

RedeemDeck 不包含账户系统、分析 SDK、广告 SDK、自建后端、CloudKit 容器或远程推送服务。SwiftData 数据库保存在 App 沙盒中。网络访问仅用于查询 App Store 元数据与图标，以及打开用户明确选择的链接。

跨设备迁移由用户主动完成：先导出备份，再在另一台设备恢复。`.redeemdeckbackup` 文件包含完整、未遮挡的兑换码，而且 RedeemDeck 不会额外加密该文件，因此必须将其视为敏感数据妥善保管。上游 CodeVault 生成的旧备份仍可通过兼容格式导入。

## 环境要求

- Xcode 26.1 或更高版本
- iOS 或 iPadOS 17.0 或更高版本
- macOS 14.0 或更高版本
- 安装到真机时需要 Apple Developer Team

项目没有任何第三方 Package 依赖。

## 编译与运行

```sh
git clone https://github.com/jinwandalaohu66/RedeemDeck.git
cd RedeemDeck
open RedeemDeck.xcodeproj
```

在 Xcode 中：

1. 选择 `RedeemDeck` Target。
2. 在 **Signing & Capabilities** 中选择自己的 Team。
3. 如果你的 Team 无法使用 `app.pythonide.redeemdeck`，请换成自己拥有的 Bundle Identifier。
4. 选择模拟器、iPhone、iPad 或 **My Mac**，然后运行 App。

修改 Bundle Identifier 会生成一个独立安装和独立本地数据库。删除现有版本前，请先导出备份。

## CSV 格式

App Store Connect 导出的文件可以直接导入。最小兼容示例：

```csv
Offer Code,Redemption URL
EXAMPLECODE,https://apps.apple.com/redeem?ctx=offercodes&id=123456789&code=EXAMPLECODE
```

第一列可以命名为 `Code`、`Offer Code` 或 `Promo Code`。如果 CSV 不包含兑换链接，请在导入时选择目标 App，RedeemDeck 会自动生成链接。不要向仓库提交真实兑换码、导出的备份、签名材料或 App Store Connect 密钥。

## 技术架构

- SwiftUI：原生导航、列表、Alert、菜单和分享
- SwiftData：本地持久化
- Swift Concurrency 与模型 Actor：解析、持久化、海报渲染和文件操作
- UserNotifications：本地提醒
- Core Image、Vision 与 Photos：二维码生成、扫码验证和海报导出

每项功能的唯一入口、状态所有者和兼容边界记录在 [Documentation/FEATURE_CATALOG.md](Documentation/FEATURE_CATALOG.md)，完整重建过程记录在 [Documentation/REBUILD_MIGRATION.md](Documentation/REBUILD_MIGRATION.md)。

## 验证

无需签名即可编译 iOS Target：

```sh
xcodebuild \
  -project RedeemDeck.xcodeproj \
  -scheme RedeemDeck \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

在 macOS 上运行确定性的核心测试：

```sh
xcodebuild \
  -project RedeemDeck.xcodeproj \
  -scheme RedeemDeck \
  -destination 'platform=macOS' \
  -only-testing:RedeemDeckTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 贡献与安全

提交 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。不要在 Issue 中公开可用兑换码或凭证；安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告。

## 上游与许可

RedeemDeck 是 [mcomisso/CodeVault](https://github.com/mcomisso/CodeVault) 的大幅修改版本，重建基于上游提交 `bf07e2c720c851aaf032ae0fd2244572a037b6c4`。完整归属说明见 [NOTICE.md](NOTICE.md)。

源码依照 [MIT License](LICENSE) 开放。许可文件保留原作者版权，并将 RedeemDeck 的修改部分标记为 copyright © 2026 WENLUZHANG。项目名称和官方身份使用说明见 [TRADEMARKS.md](TRADEMARKS.md)。
