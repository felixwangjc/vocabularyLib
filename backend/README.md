# 每日俚语服务

FastAPI / Cloud Run + Firestore + Cloud Storage。入口 `GET /v1/slang/daily`，业务时区 Asia/Shanghai，同一天返回同一条俚语及情景；随机轮播，并排除此前 60 个自然日的已选俚语。无账号要求。池内无符合条件的内容返回 503，不重复旧内容；连续每天供稿至少需要 61 条不同俚语。

已上线：[每日俚语接口](https://daily-slang-api-590936940507.asia-southeast1.run.app/v1/slang/daily)。部署验证记录见 [DEPLOYMENT.md](DEPLOYMENT.md)。

内容管理后台已上线：[打开管理后台](https://daily-slang-admin-590936940507.asia-southeast1.run.app)。支持标题、情景对话与图片的增删改、草稿和发布；登录与使用说明见 [ADMIN.md](ADMIN.md)。

## 资源

- Project ID：`gen-lang-client-0121441915`，编号 `590936940507`
- 区域：`asia-southeast1`（新加坡）
- Cloud Run：`daily-slang-api`，0–2 实例，512 MiB，1 vCPU
- Firestore：独立命名数据库 `daily-slang`，已配置删除保护
- 已发布插图桶：`gen-lang-client-0121441915-daily-slang-published`，公开只读
- 草稿桶：`gen-lang-client-0121441915-daily-slang-drafts`，私有且禁止公开访问
- 运行身份：`daily-slang-api`，仅获目标数据库的数据访问权限
- 构建身份：`daily-slang-build`，Cloud Run Builder

云资源是否成功建立及线上地址以 `DEPLOYMENT.md` 验证记录为准。代码上传白名单仅包含 Dockerfile、运行依赖和 app；草稿、插图原件、凭据、iOS 代码都不会进入镜像。

## 开发与测试

```sh
cd backend
python3.13 -m venv .venv
.venv/bin/pip install -r requirements-dev.lock
.venv/bin/python -m pytest -q
```

## 部署

前提：安装 Google Cloud CLI，执行 `gcloud auth login`，账号拥有目标项目资源管理权限，项目已启用计费。

```sh
.venv/bin/python provision.py --project gen-lang-client-0121441915 --deploy
```

此命令创建上述独立资源、配置最小运行权限和客户端拒绝规则，再从源码构建部署。它不删除现有资源。可用 `--gcloud /path/to/gcloud` 指定 CLI。`--region` 只用于首次资源选择，不用于迁移现有数据库或桶。

仅更新服务代码时：

```sh
gcloud run deploy daily-slang-api --project gen-lang-client-0121441915 \
  --region asia-southeast1 --source . \
  --build-service-account projects/gen-lang-client-0121441915/serviceAccounts/daily-slang-build@gen-lang-client-0121441915.iam.gserviceaccount.com
```

不需要把 Google Cloud 凭据写入 App。CLI 登录与服务运行身份分离；服务端使用 Cloud Run 提供的身份。

## 发布内容

复制 `content/seed.json` 的结构，一条俚语可有 1–10 个情景，每个情景 1–12 行对话和一张 PNG/JPEG/WebP 插图。图片 localFile 相对于 JSON 文件目录，最大 5 MiB、最长边 4096px；至少一行标记 isTarget。

```sh
.venv/bin/python publish.py content/seed.json \
  --project gen-lang-client-0121441915 \
  --bucket gen-lang-client-0121441915-daily-slang-published \
  --gcloud gcloud --validate-only

.venv/bin/python publish.py content/seed.json \
  --project gen-lang-client-0121441915 \
  --bucket gen-lang-client-0121441915-daily-slang-published \
  --gcloud gcloud
```

校验所有内容后再上传图片，最后事务发布不可变版本及更新选词池。重复执行相同版本无副作用；更新正文或图片时必须提升 revision，如 r2。普通内容更新不修改当天推荐。新增俚语在下一轮加入；当前库仅一条示例时用完后会返回暂无内容，需继续发布不同俚语。去重使用稳定 slangId，不应通过更换 ID 重复发布同一俚语。

`--gcloud` 在本机内存中获取短期 token，不输出或保存 token。省略时使用 ADC，适合受控发布环境。长批次应使用 ADC，避免一次性 token 到期。草稿可保留本地或上传私有 drafts 桶；脚本只把审核后指定的文件发布到公开桶。

## 接口与缓存

App 全屏启动页使用新增的 `GET /v1/slang/batch`：每次最多返回两条不同俚语，供当前展示及下一次备用。`exclude` 为上次或当前俚语 ID（最多一个）；`known` 为本地已有 ID（逗号分隔，最多 120 个），服务端优先随机选择未缓存内容。该接口只读，不消耗或提前生成每日全局推荐，返回 `no-store`。只有一条合格内容时返回一条，全部排除时返回空数组。

客户端持久化最近 120 条内容及配图，优先从本地立即展示。近 60 天未展示过的内容优先；没有时按最新产品规则回退为缓存随机回看，但不能与上次同 ID 或同俚语文字。缓存只有上次一条时跳过，保持每天最多展示一次。60 天严格服务端去重仍适用于旧 `/daily` 接口，不适用于缓存回看。

响应模型和字段见根目录 `DAILY_SLANG_DESIGN.md`。无查询参数；服务端决定日期。不支持客户端自行指定 date、timezone 或 uid。

HTTP 200 包含 ETag 和最长 300 秒的缓存时间（不会超过午夜）。If-None-Match 命中返回 304。无可用内容或数据库暂时失败返回 503、Retry-After 和 requestId。接口只返回展示数据，没有远程写入入口。图片 URL 含版本，可长期缓存。

```sh
.venv/bin/python smoke_test.py https://YOUR_SERVICE_URL
```

会验证 12 个并发请求一致、304、非法查询 400、实际插图下载。

## 运维

Cloud Run 自动收集请求与应用异常日志，X-Request-ID 可关联应用日志。当前设最大 2 实例、最小 0 实例；这是资源约束，不是费用硬上限，也不是按用户限流。公开接口未加入 App Check 或用户鉴权。

预算告警金额、通知邮箱尚未配置。正式扩大使用前，应根据用户规模配置预算告警和错误率通知。插图流量、构建、镜像存储、数据库操作均可能计费。

紧急撤稿须由管理员替换当日 dailyPicks 的 payload 并递增 contentRevision，客户端最多 5 分钟更新。不可变图片原则上不覆盖；真正需要移除公开素材时另外执行受控撤稿流程，并考虑客户端已有离线缓存无法远程抹除。

回滚服务代码可在 Cloud Run 将流量切回上一修订版；不会回滚内容数据。不得删除数据库来重置推荐，应用已启用数据库删除保护。

示例插图为内置 image_gen 生成，原图、压缩版本及完整提示词见 `content/ILLUSTRATION.md`。
