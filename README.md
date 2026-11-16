# 人工智能训练师三级答题助手 · Mac 版

Mac 原生菜单栏应用。截图识别人工智能训练师三级题目，在鼠标旁显示答案。

[下载 Mac 版 v0.1.4](https://github.com/huxi7/ai-trainer-level3-mac/releases/download/v0.1.4/AI-Trainer-Level3-Mac-v0.1.4-arm64.zip) · [发布说明](https://github.com/huxi7/ai-trainer-level3-mac/releases/tag/v0.1.4)

## 功能

- 在题目位置右键，截图并识别题干和全部选项。
- 支持单选、多选、判断题；判断题显示“正确”或“错误”。
- 支持选项乱序，按答案内容映射当前页面字母。
- 可截取右键所在窗口或鼠标所在屏幕。
- 匹配阈值可调，可开关答案旁的匹配度显示。
- 浮字无背景，字号、透明度和显示时长可调，设置自动保存。
- 本地 OCR 和 SQLite 题库，截图不上传。

## 启动

需要 Apple Silicon Mac、macOS 14 或更新版本。下载 ZIP，解压后打开“三级解题助手.app”。

从源码构建还需要 Swift 命令行工具：

```sh
zsh scripts/build_app.sh
open build/三级解题助手.app
```

启动时短暂显示“应用启动”，菜单栏出现“答”。允许应用的屏幕录制和输入监控权限，然后在题目页面右键。菜单提供匹配设置、浮字设置、权限检查和退出。

在“答 → 浮字设置”拖动“显示时长”滑块，可设置答案显示 0.1–3 秒，每次调整 0.1 秒，默认 2.5 秒。设置自动保存，下次显示答案时生效。

匹配阈值默认 60%，可调 40%–95%。阈值越低，越容易出答案，也更容易误匹配。匹配度表示文字相似度，不是答对概率。缺少整项、关键数字或否定词不一致、答案难以区分时显示“无”。

构建使用固定本地签名标识。若系统权限开关已开而应用报告未允许，重新启用该权限并重启应用。

## 题库

来源：[腾讯教育人工智能训练师练习](https://tx.jiexunkeji.net/app/index.php?i=36&c=entry&classes_id=0&do=practice_list&m=online_testapp&typeid=95&secondid=109&thirdid=112)。

六套题库共 **2,165 条**，去重后 **2,164 题**，没有答案冲突。保留源站原文、选项、答案内容、解析和来源题号。

| 文件 | 内容 |
| --- | --- |
| `data/raw/` | 原始接口数据和题目清单 |
| `data/questions.sqlite` | 去重题库及来源记录 |
| [data/questions.md](data/questions.md) | 可读题库 |
| [data/checks.json](data/checks.json) | 数量与冲突检查 |
| [data/matching-checks.md](data/matching-checks.md) | 真实截图检查结果及验证范围 |

重新整理题库：`python3 scripts/build_bank.py`。

## 技术栈

Swift + AppKit + Vision + ScreenCaptureKit + SQLite；Python 负责题库整理。

当前版本 **0.1.4**。Chrome 多选前五题的原生截图均通过匹配检查；检查结果不代表全题库准确率。
