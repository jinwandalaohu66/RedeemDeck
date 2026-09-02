# CodeVault / 兑换码管家

CodeVault 是一款面向 App Store 开发者的本地兑换码管理 App。它把 App Store Connect 导出的 CSV 整理为按 App、产品和优惠分类的库存，并提供一个直接的取码流程。

## 功能

- 从 App Store Connect CSV 导入兑换码
- 按 App 和兑换码分类管理不同订阅、折扣或活动
- 指定数量取码，并优先选择较早过期的兑换码
- 复制兑换码、复制兑换链接或保存兑换海报
- 生成带 App 图标、到期时间和自定义祝福语的二维码海报
- 保留未完成的取码记录，稍后继续处理
- 搜索、筛选、归档和恢复原始兑换码
- 本地到期提醒
- 完整备份导出与合并恢复
- 简体中文和英文界面

## 状态

CodeVault 只使用四种有效状态：

- **可用**：仍在库存中
- **待发送**：已经取出，但尚未完成复制、分享或海报保存
- **已发送**：已经通过 CodeVault 完成输出
- **已过期**：超过兑换码到期时间

“已发送”表示兑换码已经离开本地库存，不表示 App Store 已确认兑换。CodeVault 不通过访问兑换链接猜测兑换结果，也不要求 App Store Connect API Key。

## 技术栈

- SwiftUI
- SwiftData
- Swift Concurrency
- UserNotifications
- Core Image、Vision 和 Photos

项目没有第三方 Package 依赖。数据默认保存在本机 App 沙盒中，不使用账户、CloudKit、自建服务器或远程推送。换机或删除 App 前请先导出备份。

## 运行

要求 Xcode 26.1 或更高版本，支持 iOS / iPadOS 17.0 及以上版本和 macOS。

1. 用 Xcode 打开 `CodeVault.xcodeproj`。
2. 选择 `CodeVault` Target，在 **Signing & Capabilities** 中选择自己的 Team。
3. 确认 Bundle Identifier 对该 Team 唯一。
4. 选择模拟器或已连接的 iPhone，点击 Run。

## CSV 示例

```csv
Code,Redemption URL
EXAMPLE-CODE,https://apps.apple.com/redeem?id=123456789&code=EXAMPLE-CODE
```

如果 CSV 不包含兑换链接，导入时需要先选择 App。请勿把真实兑换码、App Store Connect 私钥或签名文件提交到仓库。

## 测试

```sh
xcodebuild \
  -project CodeVault.xcodeproj \
  -scheme CodeVault \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

架构入口和兼容边界见 [`Documentation/FEATURE_CATALOG.md`](Documentation/FEATURE_CATALOG.md)，重建说明见 [`Documentation/REBUILD_MIGRATION.md`](Documentation/REBUILD_MIGRATION.md)。

## 上游与许可

本项目基于 [mcomisso/CodeVault](https://github.com/mcomisso/CodeVault) 修改，重建起点为上游提交 `bf07e2c720c851aaf032ae0fd2244572a037b6c4`。代码依照 [MIT License](LICENSE) 发布；分发修改版时请保留原版权声明和许可文本。
