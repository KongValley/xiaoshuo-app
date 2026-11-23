# 墨读 · MoDu Reader

一个用 Flutter 编写的本地 TXT 小说阅读器。无需联网、无需账号：把小说导入书库，自动分章，安静地读。Windows 桌面与 Android 均可运行；Android 使用系统文件选择器（SAF）导入。

## 功能

- **本地导入**：桌面端内置文件浏览器（多选、路径输入、快捷访问、磁盘切换）；Android 端调用系统文件选择器（Storage Access Framework）。文件会复制进应用自己的书库，原文件移动/删除不影响阅读。
- **编码自动识别**：UTF-8（含 BOM / 轻微损坏）、UTF-16 LE/BE、GBK/GB2312；不会把 GBK 误判成 UTF-8。
- **自动分章**：支持 `第12章` / `第十二回` / `001 标题` / `Chapter 12` / `序章` `楔子` `番外` 等格式；无章节的书会按段落自动分节。文件名里的站点前缀、作者信息会自动清理。
- **书架**：最近阅读/导入时间/书名排序，阅读进度、章节位置、书籍信息与删除。
- **沉浸阅读**：分页排版、章节标题页、5 种阅读主题、3 款内置字体、字号/行距调节、目录搜索、进度拖动跳转。
- **翻页方式**：点击左右区域、左右滑动、鼠标滚轮、方向键/空格/PageUp/PageDown；`M` 菜单、`T` 目录、`S` 排版、`N` 夜间、`Esc` 返回。
- **进度保存**：翻页后自动保存章节与字符位置，下次打开直接回到上次读到的地方。
- **离线**：所有书籍、设置、进度都保存在本机。

## 运行

```bash
flutter pub get
flutter run -d windows
```

构建发行版：

```bash
flutter build windows --release
# 产物：build\windows\x64\runner\Release\modu_reader.exe
```

构建 Android APK（需要 JDK 17+，通过 `JAVA_HOME` 指定）：

```bash
flutter build apk --release
# 通用包，约 56 MB
flutter build apk --release --split-per-abi
# 按 ABI 拆分，约 21–25 MB/个

# 产物目录：build/app/outputs/flutter-apk/
```

Flutter 模板默认用 debug keystore 签名 release 构建，适合本地安装；如需上架应用商店，请在 `android/app/build.gradle.kts` 配置自己的 release 签名。

测试：

```bash
flutter test
```

- 示例文件 `[sxsy.org]末世第一狠人.txt` 放在项目根目录即可被 `test/real_novel_test.dart` 用来做真实文本解析校验（文件不存在时该测试自动跳过）。
- `tool/txt_report.dart` 可以查看任意 TXT 的分章报告。
- `tool/seed_library.dart` 可以把一本 TXT 直接写入本地书库，方便调试和截图。

## 数据目录

| 平台 | 位置 |
| --- | --- |
| Windows | `%LOCALAPPDATA%\ModuReader` |
| macOS | `~/Library/Application Support/ModuReader` |
| Linux | `$XDG_DATA_HOME/modu-reader` 或 `~/.local/share/modu-reader` |
| Android | 应用私有 files 目录（由系统提供；主用户为 `/data/user/0/com.modu.modu_reader/files`，工作资料、隐私空间等按实际用户区分） |

可用环境变量 `MODU_DATA_DIR` 覆盖（测试与调试用）。目录内容：

```
ModuReader/
  library.json          # 书架元数据与阅读进度
  library.json.bak      # 上一次成功写入的索引副本
  settings.json         # 阅读主题 / 字号 / 行距 / 字体 / 排序
  books/<id>/
    content.txt         # 规范化后的 UTF-8 正文（段落一行、两字缩进）
    chapters.json       # 章节标题与字符偏移
    book.json           # 这本书自己的元数据与进度
```

索引先写临时文件再替换，不会因中断而只写一半。启动时如果索引读不出来，会依次退回备份副本、再扫描 `books/` 找回未登记的书，并在书架上说明恢复情况。

## 项目结构

```
lib/
  core/                 路径、格式化、主题与三套阅读字体排版
  data/
    models/             Book / Chapter / ReaderSettings
    txt/                编码识别、TXT 规范化与分章
    library_repository  书库导入、复制、进度持久化
    settings_repository 设置持久化
  features/
    bookshelf/          书架、书卡、书籍信息
    import/             桌面端内置文件浏览器
    reader/             分页器、阅读控制器、阅读页、目录/设置面板
  data/native_import.dart  Android 系统文件选择器桥接
tool/                   分章报告与书库播种脚本
assets/fonts/           OFL 授权的阅读字体子集与许可说明
```

## 字体

内置三款 SIL OFL 1.1 授权的字体子集：**文楷**（霞鹜文楷 GB）、**宋体**（Noto Serif SC）、**黑体**（思源黑体 SC）。为控制体积按常用汉字子集化，并按 OFL 要求重命名。完整许可见 [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) 与 [`assets/fonts/NOTICE.md`](assets/fonts/NOTICE.md)。

## 已知限制

- 暂无书签、笔记、TTS、EPUB 等扩展功能。
- 超长单章（> 2 万字）会自动拆成「（续 N）」章节，避免一次排版过大。
- Android release 构建目前使用 debug 签名，适合本地安装；上架前请配置正式签名。
