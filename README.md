# VocabularyLib

iOS 原生 SwiftUI 单词本学习 App，本地优先，支持离线查词、收藏、复习、OCR 识词与例句自动补充。

**仓库**：https://github.com/felixwangjc/vocabularyLib  
**目标平台**：iOS 17.0+，iPhone / iPad  
**Bundle ID**：com.vocabularylib.app

## 功能概览

- **本地查词**：内置 `ecdict.sqlite`，770,611 条词条，离线即可查词、查音标、中英文释义。
- **例句补充**：本地 WordNet 3.0 示例库 16,454 词，优先本地；缺失时在线补充，异步更新不打断使用。
- **单词本管理**：收藏、删除、搜索、复习统计。数据持久化到 UserDefaults。
- **复习系统**：间隔重复，支持每日复习、到期提醒、复习历史记录。
- **OCR 识词**：摄像头拍照、相册导入、剪贴板图片粘贴，自动识别英文单词并加入单词本。
- **发音**：系统英文朗读。
- **Widget**：单词本小组件。
- **URL Scheme**：`vocabularylib://review` / `vocabularylib://add`。
- **系统词典联动**：长按可打开系统词典。

## 项目结构

```
VocabularyLib/          # 主 App
  Models/ WordEntry.swift, ReviewRecord.swift
  Services/ DictionaryService.swift, LocalDictionary.swift
  Stores/ VocabularyStore.swift
  Views/ ContentView.swift, WordCard, ReviewView, SettingsView, CameraOCRView...
VocabularyWidget/       # 小组件扩展
VocabularyLibUITests/   # UI 测试
Scripts/
  build_ecdict.py        # ECDICT CSV -> SQLite
  build_examples.py      # WordNet -> examples.sqlite
Resources/
  ecdict.sqlite
  examples.sqlite
```

## 本地词典

- 数据来源：https://github.com/skywind3000/ECDICT
- 版本：`bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b`
- 表结构：`words(word, phonetic, english, chinese, example)`
- 重新生成：
```sh
python3 Scripts/build_ecdict.py /path/to/ecdict.csv /path/to/new-ecdict.sqlite
```

## 例句库

- WordNet 3.0 示例库，脚本 `Scripts/build_examples.py`
```sh
python3 Scripts/build_examples.py wordnet.zip output-dir
```
输出 `examples.sqlite` 与 `WordNet-LICENSE.txt`。

## 开发

- Xcode 打开 `VocabularyLib.xcodeproj`
- iOS 17.0+，Swift 5.0
- 签名：Automatic，Development Team VN4X5HF5ZJ
- 构建产物包含 SQLite 与许可证

## 验证

```sh
swiftc VocabularyLib/Models/WordEntry.swift VocabularyLib/Services/LocalDictionary.swift Scripts/VerifyLocalDictionary.swift -o /tmp/verify-local-dictionary
/tmp/verify-local-dictionary VocabularyLib/Resources/ecdict.sqlite
```

## 配置说明

- 当前为本地版，已移除 CloudKit。保留的 iCloud 参考见 `ICLOUD_SETUP.md`。
- 本地词典说明见 `LOCAL_DICTIONARY.md`。

## 每日俚语后端

GCP 服务代码、内容发布脚本和部署说明见 [backend/README.md](backend/README.md)。
存储与 API 设计见 [DAILY_SLANG_DESIGN.md](DAILY_SLANG_DESIGN.md)。
当前 SwiftUI App 尚未接入此接口。

内容管理后台已部署，支持标题、情景对话与插图增删改；使用说明见 [backend/ADMIN.md](backend/ADMIN.md)。

## License

ECDICT 数据遵循上游 LICENSE，WordNet 许可证随 App 分发并可在设置中查看。
