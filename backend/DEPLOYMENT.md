# GCP 部署记录

## 2026-09-22：缓存预取接口

修订版 `daily-slang-api-00004-wx2` 已接收 100% 流量，新增只读 `/v1/slang/batch`（最多两条、优先未缓存、排除上次 ID）。14 项后端测试通过。上线实测无排除时返回一条 `honestly-valid`，排除该 ID 时返回空数组；当前发布池尚不足以提供不同的备用内容，需至少再发布一条。iOS 全屏明暗 UI、当天不重复展示及缓存回退单元测试通过；Mac 构建通过。

## 2026-09-22：60 天去重更新

每日服务修订版 `daily-slang-api-00003-tl2` 已部署并接收 100% 流量。生成新的每日推荐时，事务读取前 60 天的选择记录，排除这些俚语；无合格内容返回 503。已生成的当日快照不重写。客户端同时阻止最近 60 天相同 ID 或标准化俚语再次展示。本次后端 13 项测试通过（包括 150 天连续抽取的 60 天排重）。下文较早的“单条内容每天重复”和“App 尚未接入”仅为历史状态，不再代表当前实现。

部署日期：2026-09-21。状态：已上线并通过公网验证。

## 可用接口

- 每日俚语：https://daily-slang-api-590936940507.asia-southeast1.run.app/v1/slang/daily
- 健康检查：https://daily-slang-api-590936940507.asia-southeast1.run.app/health
- OpenAPI：https://daily-slang-api-590936940507.asia-southeast1.run.app/openapi.json

```sh
curl 'https://daily-slang-api-590936940507.asia-southeast1.run.app/v1/slang/daily'
```

GET，无需登录或 API key。返回英文俚语、中译、场景标题、完整中英对话、对应插图 URL、业务日期及下次刷新时间。北京时间每天零点换日，当天不变。

## 资源

| 项目 | 部署结果 |
| --- | --- |
| GCP Project ID | gen-lang-client-0121441915 |
| 项目编号 | 590936940507 |
| 区域 | asia-southeast1 |
| Cloud Run 服务 | daily-slang-api |
| 当前修订版 | daily-slang-api-00002-j89，100% 流量 |
| Firestore | daily-slang，Native / Standard，已启用删除保护 |
| 已发布图片桶 | gen-lang-client-0121441915-daily-slang-published |
| 私有草稿桶 | gen-lang-client-0121441915-daily-slang-drafts |
| 运行配置 | 0–2 实例、1 vCPU、512 MiB、并发 40、请求超时 30 秒 |

[Cloud Run 控制台](https://console.cloud.google.com/run/detail/asia-southeast1/daily-slang-api/metrics?project=gen-lang-client-0121441915)

## 已验证

- 本地 6 项测试通过：换日、轮播去重、池变更、缓存、错误响应、发布校验。
- 首次 12 个并发业务请求全部 HTTP 200、响应体一致；Firestore 仅有 1 条 dailyPick，轮播 cycle=1。
- 最终修订版再次通过 smoke_test.py：健康检查 200、12 个并发请求一致、条件请求 304、非法参数 400。
- 插图匿名下载 HTTP 200，JPEG 1024×1024，243,075 字节。
- 规则 API 确认已发布 `allow read, write: if false`；匿名 Firestore 直连返回 403。
- 相同示例二次导入返回 Already published，未新增版本。
- 大字段 scenarios / payload / entries / remainingIds 已配置无索引豁免。

健康检查采用 `/health`，避开 Cloud Run 的保留路径；参考 [官方路径限制](https://docs.cloud.google.com/run/docs/known-issues#reserved-url-paths)。

## 当前内容和边界

已发布 1 条示例：Honestly, valid. / after-work-ramen，包含 4 行中英对话和 AI 生成卡通插图。当前仅一条内容，所以每天会重复；通过 publish.py 增加内容后即可随机轮播。没有把截图当成完整 200 条词库进行虚构导入。

App 尚未接入，当前交付为可供 App 调用的线上服务。内容发布、部署更新和测试命令见 [README.md](README.md)。插图原图及压缩版本见 content/assets，内置 image_gen 的完整提示词见 [ILLUSTRATION.md](content/ILLUSTRATION.md)。

Cloud Logging 已有请求与异常日志。尚未设置预算金额和告警通知渠道；最大实例数不是账单硬上限。没有启用 App Check 或用户级限流。

本次使用官方 Google Cloud SDK，临时 CLI 包装入口为 `/tmp/daily-slang-tools/gcloud`，登录配置也在该临时目录，未写入项目或镜像。后续本机维护可安装持久版 gcloud 并自行登录，或在该临时目录仍存在时用 `--gcloud /tmp/daily-slang-tools/gcloud`。

## 2026-09-22：管理后台

- 地址：https://daily-slang-admin-590936940507.asia-southeast1.run.app
- Cloud Run：daily-slang-admin，修订版 daily-slang-admin-00002-2jz，100% 流量。
- 独立运行身份 daily-slang-admin，0–2 实例，512 MiB；存储和凭据权限与公开 API 隔离。
- Secret Manager 保存密码摘要和会话密钥；登录信息在本机 backend/.admin-access.txt，权限 0600、Git 忽略、构建排除。
- 12 项本地测试通过。线上完整验证通过：登录/匿名拒绝、私有图片上传预览、添加草稿、标题与对话编辑、发布、版本冲突拒绝、引用中图片拒删、移除配图、删除图片、删除内容。
- 目视检查登录页、内容列表、编辑页及配图区域；测试临时内容和上传图片均已清理，后台保留原有 1 条正式示例。
- 原有公开每日接口继续工作，未编辑原始示例内容。

后台管理已替代手工脚本作为日常维护入口，操作说明见 [ADMIN.md](ADMIN.md)。
