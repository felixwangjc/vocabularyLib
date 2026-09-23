# 每日俚语：GCP 存储与 API 设计

最新缓存策略（2026-09-22）：启动页改为全屏、隐藏滚动指示器，客户端优先展示本地内容和配图，通过 `/v1/slang/batch` 后台获取最多两条作为后备。优先近 60 天未看过的内容；无新内容时允许随机回看缓存，但不与上次相同，每天仍最多展示一次。本规则覆盖下文早期严格 60 天不重复、过期缓存不可展示的启动页约定。`/daily` 保留原行为。配套接口与部署验证见 backend/README.md、backend/DEPLOYMENT.md。

状态：后端已部署到 GCP；2026-09-22 SwiftUI iOS / macOS 已接入每日首次前台打开的俚语卡片。最新实现覆盖下文首版旧约定：服务端在事务中查询前 60 个自然日 dailyPicks，排除其 slangId；不足时返回 503。客户端按业务日期每天最多展示一次，并按 ID 和标准化俚语文字再次过滤近 60 天内容，实际显示时落盘记录。断网仅允许使用未过期的当天缓存，否则跳过弹窗；图片失败可重试，始终允许关闭。不会伪造旧内容为今日推荐。线上接口及部署记录见 [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md)。下文保留首版架构说明，重复策略以本段最新规则为准。

## 1. 首版约定

- 每天返回一条俚语及一个完整情景对话；每个情景绑定自己的卡通插图。
- 默认所有用户当天看到同一条，按 Asia/Shanghai 的零点换日；由服务端时钟决定，不信任手机日期。此为产品默认值，可在上线前调整。
- 当天重复请求稳定；采用随机洗牌轮播，一轮内不重复俚语。内容只有一条时允许每天重复。
- 图片预先制作、审核并上传，不在用户请求时生成。
- 截图仅作为内容结构参考，并非完整数据集；其中语言自然度、释义和适用语境需在发布前校对。

## 2. 架构

```text
SwiftUI App -- HTTPS / JSON --> Cloud Run API --> Firestore
     |
     +-- HTTPS 图片下载 --> Cloud Storage（已发布图片桶）

管理员导入脚本 --> 私有草稿素材桶 + Firestore 草稿
管理员发布脚本 --> 已发布图片桶 + 不可变内容版本 + 选词池
```

建议后端使用 Python / FastAPI，部署到 Cloud Run；Firestore Native mode 存结构化数据，Cloud Storage 存图片。首版无需 Cloud SQL、Redis 或定时任务。Cloud Run、Firestore、Storage 尽量选择相近区域；上线前以实际目标用户所在地验证 API 和图片可达性、延迟，尤其是中国大陆网络。

## 3. Firestore 集合

| 路径 | 用途 | 主要字段 |
| --- | --- | --- |
| `slangs/{slangId}` | 内容编辑、发布入口 | phrase、meaningZh、category、tags、usageNoteZh、status、currentRevision、createdAt、updatedAt |
| `slangs/{slangId}/revisions/{revision}` | 不可变的已发布版本 | phrase、meaningZh、category、usageNoteZh、scenarios、publishedAt |
| `catalogs/daily` | 当前可抽取内容，首版约几百条 | revision、entries: [{slangId, revision}] |
| `rotationStates/global` | 跨天轮播进度 | remainingIds、lastSlangId、cycle、catalogRevision |
| `dailyPicks/{yyyy-MM-dd}` | 每日固定选择及内容快照 | date、timezone、slangId、revision、scenarioId、payload、createdAt |

一个俚语可以有多个情景。首版把情景数组放在版本文档里，每个情景有稳定 ID、标题、对话和图片元数据。图片属于情景，而不是俚语；此处“一例句”按截图理解为一整段情景对话。未来若每一行台词都需独立图片，可在 line 上增加 illustration。

示例版本文档（示例图片路径尚无真实文件）：

```json
{
  "phrase": "Honestly, valid.",
  "meaningZh": "完全合理；我完全能理解。",
  "category": "affirmation",
  "usageNoteZh": "非正式口语，用来表示理解或认可对方的选择。",
  "scenarios": [
    {
      "id": "after-work-ramen",
      "titleZh": "累了一天，只想在家休息",
      "lines": [
        {"id": "l1", "speaker": "A", "en": "I skipped the after-party just to eat ramen and watch anime in bed.", "zh": "我没去续摊，就想窝在床上吃拉面、看动漫。", "isTarget": false},
        {"id": "l2", "speaker": "B", "en": "After a twelve-hour shift? Honestly, valid.", "zh": "上了十二个小时的班？完全能理解。", "isTarget": true},
        {"id": "l3", "speaker": "A", "en": "I thought you'd call me boring.", "zh": "我还以为你会说我无聊。", "isTarget": false},
        {"id": "l4", "speaker": "B", "en": "Nah, protect your peace at all costs.", "zh": "不会，让自己舒心最重要。", "isTarget": false}
      ],
      "illustration": {
        "objectPath": "slangs/honestly-valid/r1/after-work-ramen/illustration.webp",
        "contentType": "image/webp",
        "width": 1024,
        "height": 1024,
        "altZh": "一位下班后的年轻人窝在床上吃拉面、看动漫，朋友表示理解。"
      }
    }
  ]
}
```

Firestore 时间字段使用 Timestamp，HTTP 输出为 ISO 8601。发布脚本限制每篇最多 10 个情景、每个情景最多 12 行，并验证序列化大小小于 256 KiB，为文档上限留余量。仅对真正查询的字段建索引；对 scenarios、payload、entries 和 remainingIds 等大数组或映射关闭不需要的索引。未来规模增大时再把情景、选词池和轮播队列拆分，不能让单文档无限增长。

## 4. 图片策略

- 草稿和原始大图存私有桶；只有已发布的插图复制到单独的公开图片桶。该方案适合免费公开学习内容。
- 数据库仅存 objectPath 和尺寸等元数据，API 根据配置生成 HTTPS URL。不存二进制、Base64 或会过期的签名 URL。
- 文件名包含内容版本；更新图片产生新路径，避免 App 缓存旧图。发布图片可设 `Cache-Control: public, max-age=31536000, immutable`。
- 以 768–1024 像素宽的 WebP 为起点，以可读性实测压缩质量；目标单图约 100–250 KB，属制作预算而非系统保证。
- 若未来需要付费鉴权或组织策略禁止公开桶，则改为私有桶和短期 V4 签名 URL。API 同时返回 expiresAt，客户端过期后重新取链接；不能把该链接永久写入每日快照。签名需要读取对象和签名身份的相应权限。

## 5. 每日抽取与一致性

所有请求先计算服务端业务日期 D，读取 `dailyPicks/D`，已有记录直接返回；不能每次调用 random 导致当天内容变动。

不存在记录时，运行 Firestore 事务：

1. 再读 dailyPicks/D；若其他实例已创建，则使用该记录。
2. 读取 catalog 和 rotationState，去除剩余队列里已下架的 ID。池版本变更时保留仍有效的顺序，新加入内容留待下一轮加入。
3. 队列为空时，对当前已发布 ID 用 Fisher–Yates 洗牌；有两条及以上时避免新一轮首条等于上一轮末条。
4. 取队首俚语，读取 catalog 所指定的不可变版本；从其中合法情景均匀随机选一个，连同图片路径写入每日内容快照。
5. 原子写入每日快照及更新后的队列状态。所有读取必须在写入之前完成。

事务冲突会重试，回调内部不上传图片、不发消息，也不产生其他外部副作用。只有成功提交的选择才返回客户端。无请求的日期不消费内容；并发首次请求通过同一事务状态串行化。首版仅按“今天”抽取，不提供补生成历史日期接口。

空内容池返回明确的 503。已发布版本和图片不可原地修改，普通编辑从未来每日推荐生效。当日必须紧急撤稿时，管理员显式替换 dailyPick 并增加 revision；这属于当天稳定性约定的明确例外，缓存传播最多延迟 5 分钟。

## 6. HTTP 契约

### 获取今日内容

`GET /v1/slang/daily`

首版无必填参数、不要求用户登录，返回简体中文释义和英语内容。日期与时区由服务端控制。不接受任意日期、时区或用户 ID 来改变选择。

响应示意，image URL 为部署后的实际地址：

```json
{
  "schemaVersion": 1,
  "dailyId": "2026-09-21",
  "date": "2026-09-21",
  "timezone": "Asia/Shanghai",
  "nextRefreshAt": "2026-09-21T16:00:00Z",
  "contentRevision": 1,
  "slang": {
    "id": "honestly-valid",
    "revision": "r1",
    "phrase": "Honestly, valid.",
    "meaningZh": "完全合理；我完全能理解。",
    "category": "affirmation",
    "usageNoteZh": "非正式口语，用来表示理解或认可对方的选择。"
  },
  "scenario": {
    "id": "after-work-ramen",
    "titleZh": "累了一天，只想在家休息",
    "lines": [
      {"id": "l1", "speaker": "A", "en": "I skipped the after-party just to eat ramen and watch anime in bed.", "zh": "我没去续摊，就想窝在床上吃拉面、看动漫。", "isTarget": false},
      {"id": "l2", "speaker": "B", "en": "After a twelve-hour shift? Honestly, valid.", "zh": "上了十二个小时的班？完全能理解。", "isTarget": true},
      {"id": "l3", "speaker": "A", "en": "I thought you'd call me boring.", "zh": "我还以为你会说我无聊。", "isTarget": false},
      {"id": "l4", "speaker": "B", "en": "Nah, protect your peace at all costs.", "zh": "不会，让自己舒心最重要。", "isTarget": false}
    ],
    "illustration": {
      "url": "https://storage.googleapis.com/YOUR_PUBLISHED_BUCKET/slangs/honestly-valid/r1/after-work-ramen/illustration.webp",
      "width": 1024,
      "height": 1024,
      "altZh": "一位下班后的年轻人窝在床上吃拉面、看动漫，朋友表示理解。"
    }
  }
}
```

200 响应带 ETag，App 可发送 If-None-Match 并处理 304。JSON 的 max-age 取 300 秒与距离业务零点剩余秒数的较小值；ETag 包含日期和内容 revision，午夜后不能因正文相同误返回旧日内容。首次生成失败返回 503 和 Retry-After，不将昨天内容伪装成今天。

错误格式：`{"error":{"code":"CONTENT_UNAVAILABLE","message":"今日内容暂不可用","requestId":"..."}}`。预留 429 用于限流，500 用于未预期错误；日志记录 requestId，不向 App 暴露堆栈。

后续按需增加 `GET /v1/slang/{slangId}` 用于收藏回看。首版不暴露管理写入接口；由受 IAM 保护的发布脚本执行写操作。

## 7. 内容录入和发布

维护一个 JSON 数据文件及配套图片目录：草稿导入 → 校对中英文 → 上传对应插图 → 校验图片存在及 MIME、大小、情景关联 → 创建不可变版本 → 事务更新 currentRevision 和 catalog。

先上传图片再发布数据库记录；失败遗留的未引用图片可稍后清理。slangId、scenarioId 稳定，重复导入不重复创建内容。原图、提示词和素材授权信息可保留在私有编辑记录中，不返回给 App。首版使用脚本即可，无需先做管理后台。

## 8. App 接入

建议新增 DailySlang Codable 模型、通过 URLSession 获取数据的 DailySlangService、管理本地缓存的 DailySlangStore，以及展示句子卡片和情景插图的 DailySlangView。

App 打开页面时先展示本地缓存，同时按缓存策略请求接口。以 nextRefreshAt 为换日依据，处理 App 跨午夜保持前台和重新进入前台两种情况。断网保留上一条并标注“最近保存”，不冒充今日推荐。图片单独缓存到磁盘，缓存键使用含版本的 URL；图片失败不阻塞文字展示，保留固定比例占位图和重试入口。

情景展开时展示插图、场景标题和 A/B 对话，isTarget 行突出显示。当前本地词典和单词复习功能保持独立。

## 9. 权限、运行与成本

App 只访问 Cloud Run 的只读 API 和已发布图片。Firestore 客户端规则拒绝直接读写；后端 SDK 使用服务账号 IAM 权限，不依赖这些规则。Cloud Run 使用专用服务身份与 Application Default Credentials，不把服务账号密钥放入 App 或仓库。

公开 API 不使用硬编码 App API key 充当身份验证。可在上线前按流量需要加入 App Check 校验与限流；管理端始终独立使用 IAM。配置请求超时、最大实例数、错误率告警及预算告警；预算告警本身不是费用硬上限。

常规请求主要读取一条 dailyPick，首次请求另有事务读写；图片通常是主要流量来源。例如 10,000 次未命中图片缓存的下载、每张 150 KB，约为 1.5 GB 图片传输量。实际账单还取决于地区、缓存、调用次数及当时定价，上线前按目标流量估算，不假定永久免费。

## 10. 后续个人推荐

若每位用户每天需不同内容，增加 Firebase Authentication（可匿名）等可靠身份机制，验证 token 后使用服务端取得的 uid。选择记录改成 `users/{uid}/dailyPicks/{date}`，轮播状态也按用户保存。需明确账户时区、换时区的生效时间和历史去重保留策略。不能仅靠客户端传来的 uid 做隔离；全局公共缓存同时改为 private，避免不同用户串内容。

## 11. 实现验收

- 同一天并发首次请求，所有调用得到相同俚语和情景，仅消费一次轮播状态。
- 零点前后返回正确 date、nextRefreshAt、ETag，不复用昨日缓存。
- 一轮内无重复，跨轮有多条内容时不连续重复；覆盖空池、单条、上架与下架。
- 草稿和缺图内容无法进入发布池；图片和情景关联准确。
- 内容编辑不修改当日快照；显式紧急撤稿能在缓存期限内生效。
- iOS 覆盖离线、304、503、图片失败和重新进入前台场景。

## 参考资料

- [Firestore 数据模型](https://firebase.google.com/docs/firestore/data-model)
- [Firestore 事务及重试约束](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Cloud Run 服务身份](https://docs.cloud.google.com/run/docs/securing/service-identity)
- [Cloud Storage 公开对象](https://docs.cloud.google.com/storage/docs/access-control/making-data-public)
- [Cloud Storage 签名 URL](https://docs.cloud.google.com/storage/docs/access-control/signed-urls)
