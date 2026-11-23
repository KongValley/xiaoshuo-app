# 墨读 · MoDu Reader

一个用 Flutter 编写的本地 TXT 小说阅读器。无需联网、无需账号：把小说导入书库，自动分章，安静地读。桌面端（Windows）为完整目标平台，Android 工程已生成但导入还需接入系统文件选择器（见文末）。

## 功能

- **本地导入**：内置文件浏览器，支持多选、直接输入路径、快捷访问与磁盘切换；文件会复制进应用自己的书库，原文件移动/删除不影响阅读。
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

可用环境变量 `MODU_DATA_DIR` 覆盖（测试与调试用）。目录内容：

```
ModuReader/
  library.json          # 书架元数据与阅读进度
  settings.json         # 阅读主题 / 字号 / 行距 / 字体 / 排序
  books/<id>/
    content.txt         # 规范化后的 UTF-8 正文（段落一行、两字缩进）
    chapters.json       # 章节标题与字符偏移
```

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
    import/             内置文件浏览器
    reader/             分页器、阅读控制器、阅读页、目录/设置面板
tool/                   分章报告与书库播种脚本
assets/fonts/           OFL 授权的阅读字体子集与许可说明
```

## 字体

内置三款 SIL OFL 1.1 授权的字体子集：**文楷**（霞鹜文楷 GB）、**宋体**（Noto Serif SC）、**黑体**（思源黑体 SC）。为控制体积按常用汉字子集化，并按 OFL 要求重命名。完整许可见 [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) 与 [`assets/fonts/NOTICE.md`](assets/fonts/NOTICE.md)。

## 已知限制

- 当前主要面向 Windows 桌面。Android 工程可以编译，但内置文件浏览器直接读取共享存储在 Android 11+ 会受分区存储限制；如需 Android 完整导入，建议接入 `ACTION_OPEN_DOCUMENT`（SAF）或 `file_picker` 类插件。
- 暂无书签、笔记、TTS、EPUB 等扩展功能。
- 超长单章（> 6 万字）会自动拆成「（续 N）」章节，避免一次排版过大。
