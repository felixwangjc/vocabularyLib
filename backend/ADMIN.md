# 内容管理后台

后台地址：https://daily-slang-admin-590936940507.asia-southeast1.run.app

后台独立于公开每日接口部署。登录密码保存在本机 `backend/.admin-access.txt`，文件权限 0600，已从 Git 和构建上传列表排除；请保存在自己的密码管理器中。服务端仅保存 scrypt 密码摘要，摘要和会话签名密钥分别存于 Secret Manager。

## 使用

1. 打开后台地址，输入管理密码。
2. 在「内容管理」中添加内容，填写英文表达/标题、中文释义、分类和使用提示。
3. 编辑情景标题与 A/B 对话，每句可填写中译、标记重点；可以添加或移除情景和台词。
4. 上传配图（JPEG、PNG、WebP，最多 5 MB、最长边 4096px），填写图片说明。可替换或移除配图。
5. 保存为草稿，或将状态改成「已发布」后保存。发布内容进入每日抽取池；每个发布情景须包含配图、图片说明和重点台词。
6. 内容删除会移除整条标题及情景，并退出推荐；可选择同时删除不再被其他内容引用的图片。历史文字版本保留以便技术恢复。
7. 「图片素材」中可查看素材及引用数，删除未使用的图片。仍被草稿/发布内容引用的图片不能删除；先从编辑器移除并保存。上传后未保存的图片会留在素材库，可直接清理。

修改、转草稿或删除当天推荐内容时，会清除当日快照，下一次请求重新选择。App 已缓存的内容最长约 5 分钟更新。删除最后一条发布内容后，公开接口返回 503 CONTENT_UNAVAILABLE，而不会展示已删除内容。

删除图片会移除 GCS 活跃对象及素材区副本，不会清除用户设备已下载的图片缓存。历史版本中的旧图片可能因此不可再用；GCS 的软删除保留期以桶配置为准。图片正在发布时会短暂锁定；未完成的发布锁最长 2 分钟，之后可重试删除。

## 权限及安全

- `daily-slang-admin` 使用单独的服务身份，仅能操作 daily-slang 数据库和两个专用图片桶，并读取两个专用 Secret。
- 登录会话为 Secure / HttpOnly / SameSite=Strict Cookie，8 小时过期。
- 写操作校验固定 Origin 和 CSRF token；所有管理数据接口都要求登录。
- 连续登录尝试受 Firestore 计数限制，同一来源每 15 分钟最多 10 次。
- 静态页面使用 CSP，用户输入通过 textContent 或表单值渲染，不插入 HTML。
- 管理 API 和管理 Cookie 不存在于公开 `daily-slang-api` 服务中。
- 图片 MIME 从实际字节识别，拒绝 SVG、动图、超大及损坏文件；普通上传先进入私有桶。
- 多窗口同时编辑时，baseRevision 不一致返回 409，避免覆盖他人的修改。
- 后台只支持单个管理密码，无多用户角色管理。退出会清除当前浏览器 Cookie；失窃会话须轮换会话密钥使其失效。

## 更新部署

首次或资源重建（已有密码文件和 Secret 不会被覆盖）：

```sh
.venv/bin/python provision_admin.py --project gen-lang-client-0121441915 \
  --project-number 590936940507 --gcloud /tmp/daily-slang-tools/gcloud
```

日常更新代码，无需重建资源：

```sh
gcloud run deploy daily-slang-admin --project gen-lang-client-0121441915 \
  --region asia-southeast1 --source . \
  --build-service-account projects/gen-lang-client-0121441915/serviceAccounts/daily-slang-build@gen-lang-client-0121441915.iam.gserviceaccount.com
```

后台以 `APP_MODULE=app.admin:app` 启动，公开接口默认以 `app.main:app` 启动。不要改变公开接口的 APP_MODULE 或给它授予管理后台的图片/Secret 权限。

使用 `publish.py` 初始导入的新 ID 可以在后台打开并编辑。已由后台编辑或删除的 ID 不允许再被导入脚本覆盖；请在后台管理它们。

## 验证

本地：`.venv/bin/python -m pytest -q`。

线上端到端验证会新建临时内容和图片，执行草稿、修改、发布、版本冲突、图片删除和内容删除，再清理该测试内容；不会编辑既有内容：

```sh
.venv/bin/python admin_smoke_test.py \
  https://daily-slang-admin-590936940507.asia-southeast1.run.app \
  --public-api https://daily-slang-api-590936940507.asia-southeast1.run.app/v1/slang/daily
```

验证脚本从本地凭据文件读取密码，不打印密码或 Cookie。历史测试文字版本可能保留在已删除记录中。
