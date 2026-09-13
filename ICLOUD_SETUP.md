# iCloud 配置

> 当前工程已切换为本地版，下列内容仅保留为未来恢复 CloudKit 时的参考。当前不包含 CloudKit 服务或 entitlement，也不会自动同步。免费 Personal Team 可用于本地版签名；请在 Xcode 中选择自己的 Team 并使用自动签名生成有效的描述文件。

1. 用 Xcode 打开 VocabularyLib.xcodeproj，在 Signing & Capabilities 选择自己的开发团队并启用自动签名。
2. 启用 iCloud / CloudKit，创建并关联容器 `iCloud.com.vocabularylib.app`。若更换容器名称，需要同时修改 entitlements 和 CloudSyncService.swift。
3. 在 CloudKit Console 的 Development 数据库创建 `VocabularyWord` record type，添加 `payload` 字段（Bytes）。为系统字段 `recordName` 创建 QUERYABLE 索引，以支持全量查询。保留私有数据库的默认账户权限。
4. 发布 TestFlight / App Store 前，将 schema 和索引部署到 Production。
5. 在两台登录同一 Apple 账户的真机上验证：新增、复习、删除后手动同步，然后在另一台设备打开 App，确认合并结果。断网操作后恢复网络并手动同步，确认数据保留。

同步使用 CloudKit 私有数据库。单词按小写词形合并，同词使用最近修改记录；删除使用保留的删除标记防止旧设备重新上传。当前在启动、回到前台及手动点击时同步；修改后需要再次同步才能上传。网络失败保留本地数据，并在设置中显示错误，可再次点击重试。

本机仅有 Command Line Tools，已做 Swift 语法检查，尚未进行 iOS 构建、签名及 CloudKit 真机联调。
