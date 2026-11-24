# 拾卷 · ShiJuan Reader

一个用 Flutter 编写的本地多格式电子书阅读器。无需联网、无需账号：把本地书籍导入书库，自动分章与压缩存储，安静地读。Windows 桌面与 Android 均可运行；支持 TXT、EPUB、MOBI/AZW/AZW3、Word（`.docx` / `.doc`）与文字层 PDF。

## 功能

- **多格式本地导入**：支持导入 `.txt`、`.epub`、`.mobi`、`.azw`、`.azw3`、`.prc`、`.pdf`、`.docx`、`.doc`。桌面端内置文件浏览器（多选、路径输入、快捷访问、磁盘切换）；Android 端调用系统文件选择器（SAF）并在导入结束后自动清理临时缓存，原文件移动/删除不影响阅读。
- **编码与结构识别**：TXT 自动识别 UTF-8（含 BOM / 轻微损坏）、UTF-16 LE/BE、GBK/GB2312；EPUB / MOBI / Word / PDF 自动解析目录或标题章节并智能拼接中文折行，无章节文本自动按页或段落分节，文件名里的站点前缀与作者信息会自动清理。
- **自动分章**：支持 `第12章` / `第十二回` / `001 标题` / `Chapter 12` / `序章` `楔子` `番外` 等格式与电子书内嵌 TOC；无章节的书会按页组或段落自动分节。
- **压缩存储与批量管理**：正文统一透明 Gzip 压缩为 `content.txt.gz` 节省约 50%–75% 空间（无缝兼容旧版 `content.txt` 并支持「关于拾卷」弹窗内一键压缩迁移）；书架顶部实时显示书库磁盘占用，支持多选「批量管理」（全选、批量重置进度、批量移出书架）。
- **书架与历程**：最近阅读/导入时间/书名排序，网格与双栏列表自适应切换，格式角标、阅读进度、「拾卷印记」每日目标与连续阅读连击、8 枚朱砂篆刻印章成就墙。
- **沉浸阅读**：单页居中与宽屏双页对开自适应排版（支持`自动 / 单页 / 双页`切换）、章节标题页、5 种阅读主题、3 款内置字体、字号/行距调节、页缘丝带书签夹、目录搜索与书签双标签跳转、进度拖动跳转、圆满合卷仪式。
- **翻页与控制**：点击左右区域、左右滑动、鼠标滚轮、方向键/空格/PageUp/PageDown；`M` 菜单、`T` 目录、`B` 书签、`S` 排版、`N` 夜间、`H` 帮助、`Esc` 返回。
- **进度与书签保存**：翻页后自动保存章节与字符位置，书签与阅读历程分别本地持久化，下次打开直接回到上次读到的地方。
- **多端自适应**：一套代码自适应手机竖屏、横屏、平板及 Windows 桌面窗口；宽屏端目录自动以右侧抽屉呈现、排版工坊与印记以居中浮窗展开。
- **离线**：所有书籍、书签、设置、进度与阅读统计都保存在本机。

## 运行

```bash
flutter pub get
flutter run -d windows
```

构建发行版：

```bash
flutter build windows --release
# 产物：build\windows\x64\runner\Release\shijuan_reader.exe
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
| Windows | `%LOCALAPPDATA%\ShijuanReader` |
| macOS | `~/Library/Application Support/ShijuanReader` |
| Linux | `$XDG_DATA_HOME/shijuan-reader` 或 `~/.local/share/shijuan-reader` |
| Android | 应用私有 files 目录（由系统提供；主用户为 `/data/user/0/com.shijuan.shijuan_reader/files`，工作资料、隐私空间等按实际用户区分） |

可用环境变量 `SHIJUAN_DATA_DIR` 覆盖（测试与调试用）。目录内容：

```
ShijuanReader/
  library.json          # 书架元数据与阅读进度
  library.json.bak      # 上一次成功写入的索引副本
  settings.json         # 阅读主题 / 字号 / 行距 / 字体 / 布局 / 排序
  reading_stats.json    # 每日阅读时长、连续天数与朱砂印章解锁记录
  books/<id>/
    content.txt.gz      # Gzip 压缩存储的规范化 UTF-8 正文（无缝兼容旧版 content.txt）
    chapters.json       # 章节标题与字符偏移
    bookmarks.json      # 本书丝带书签摘录与字符位置
    book.json           # 这本书自己的元数据与进度
```

索引先写临时文件再替换，不会因中断而只写一半。启动时如果索引读不出来，会依次退回备份副本、再扫描 `books/` 找回未登记的书，并在书架上说明恢复情况。

## 项目结构

```
lib/
  core/                 路径、格式识别、品牌图标、印章绘制、响应式断点、主题与三套阅读字体
  data/
    models/             Book / Chapter / ReaderSettings / ReadingStats
    txt/                编码识别、TXT 规范化与分章
    formats/            多格式文档解析（EPUB / MOBI / AZW3 / DOCX / DOC OLE2&RTF / PDF）
    library_repository  书库导入、Gzip 压缩存储、批量管理、进度与书签持久化
    settings_repository 设置持久化
    stats_repository    阅读统计与印章成就持久化
  features/
    bookshelf/          书架、书卡、书籍信息、批量管理栏、拾卷印记成就面板
    import/             桌面端内置多格式文件浏览器
    reader/             分页器、阅读控制器（含双页对开）、阅读页、目录书签/排版面板
  data/native_import.dart  Android 系统文件选择器与缓存清理桥接
tool/                   分章报告与书库播种脚本
assets/                 应用图标图片与 OFL 授权的阅读字体子集
```

## 字体

内置三款 SIL OFL 1.1 授权的字体子集：**文楷**（霞鹜文楷 GB）、**宋体**（Noto Serif SC）、**黑体**（思源黑体 SC）。为控制体积按常用汉字子集化，并按 OFL 要求重命名。完整许可见 [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt) 与 [`assets/fonts/NOTICE.md`](assets/fonts/NOTICE.md)。

## 已知限制

- 已支持 TXT / EPUB / MOBI / AZW3 / PDF / Word 导入与丝带书签夹、批量管理；暂无划线笔记、TTS 朗读等功能。
- PDF 目前提取文档内嵌文字层并以重排文本方式阅读；纯图片扫描版 PDF（无文字层）及受 DRM/密码保护的文件无法提取正文。
- 超长单章（> 2 万字）会自动拆成「（续 N）」章节，避免一次排版过大。
- Android release 构建目前使用 debug 签名，适合本地安装；上架前请配置正式签名。
