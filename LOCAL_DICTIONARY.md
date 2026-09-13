# 本地词典

例句补充更新：新增 WordNet 3.0 本地用法示例库，16,454 个词，约 0.92 MiB。优先本地读取，再请求网络；本地示例包含短语，不保证与 ECDICT 首个义项相符。`Scripts/build_examples.py` 从 NLTK 分发的 WordNet 压缩包提取引号内的真实示例，只关联含有该词的示例，不自行生成；输入 SHA256 与原始许可证内嵌于 metadata。独立的 WordNet-LICENSE.txt 随 App 分发并可在设置查看。网络查询现遍历全部词条，区分无例句、未收录、超时、网络故障、服务端及解析错误；不缓存没有例句的返回，以便手动重试。

App 内置 `VocabularyLib/Resources/ecdict.sqlite`，770,611 个词条，约 62.3 MiB（未压缩）。索引查询只读取命中的词条，不将整个词库加载到内存。

数据来自 https://github.com/skywind3000/ECDICT ，固定版本 `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b`。上游 LICENSE 随资源打包，并可在设置页面查看。原始 CSV 校验值保存在数据库 metadata 表中。转换时保留有释义的词条，将词形转小写并合并相同词形，转换释义中的换行符。

重新生成（输出路径必须不存在）：

```sh
python3 Scripts/build_ecdict.py /path/to/ecdict.csv /path/to/new-ecdict.sqlite
```

查词流程：本地 SQLite 命中立即返回并保存；未命中才请求英文词典及中文翻译。英文请求设置 6 秒请求超时、10 秒资源超时，翻译请求设置 3 秒请求超时。在线词典响应进行有界内存缓存。发音始终使用系统英文朗读。

保存单词后在 App 运行期间异步获取例句，完成后更新同一 ID 的单词并持久化；不会因网络失败或例句缺失撤销添加。打开缺少例句的卡片会重试，也提供手动获取按钮。App 退出可能中断网络任务，不依赖系统后台执行权限。用户删除词条时迟到的响应不会重新创建单词。旧版生成的占位例句被视为缺失，真实旧例句保留。

词库部分英文释义或音标缺失，缺失字段不会伪造。在线例句从该词的可用义项中选取，尚未实现与本地义项的语义匹配。

## 验证

已通过 Xcode 26.6 的 Debug iOS Simulator 完整构建（关闭签名），并检查构建产物包含 SQLite 及许可证。未进行真机交互验收。现有 OCR Sendable 警告和主 App / Widget 版本号警告不影响本次构建。

两项独立验证可在 macOS 上运行：

```sh
swiftc VocabularyLib/Models/WordEntry.swift VocabularyLib/Services/LocalDictionary.swift Scripts/VerifyLocalDictionary.swift -o /tmp/verify-local-dictionary
/tmp/verify-local-dictionary VocabularyLib/Resources/ecdict.sqlite
swiftc VocabularyLib/Models/WordEntry.swift VocabularyLib/Services/LocalDictionary.swift VocabularyLib/Services/DictionaryService.swift Scripts/VerifyDictionaryService.swift -o /tmp/verify-dictionary-service
/tmp/verify-dictionary-service VocabularyLib/Resources/ecdict.sqlite VocabularyLib/Resources/examples.sqlite
```

服务测试使用模拟网络响应，验证本地命中零请求、例句查询及缓存、在线查询降级、无网错误和输入校验，不依赖外部服务可用性。
