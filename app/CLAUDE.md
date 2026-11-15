# app/
> L2 | 父级: ../CLAUDE.md

Bank.swift: 从只读 SQLite 读取去重题目及答案内容。
Matcher.swift: 按可调文字阈值匹配完整选项；输出答案、最低匹配度和拒绝原因。
OCR.swift: 分别读取正文与彩色按钮字母；按位置合并并归位居中字母。
OptionLabelOCR.swift: 增强并拼接实际按钮；识别字符数须与图像槽位数一致。
Capture.swift: 用事件窗口 ID 与鼠标位置定位题目窗口；也可截取整块屏幕。
Main.swift: 右键截图入口、匹配度与设置菜单；命令行可保存诊断截图。
Appearance.swift: 保存字号与透明度；菜单滑块即时预览超细答案浮字。
MatchingSettings.swift: 保存匹配阈值和匹配度开关；菜单默认阈值 60%。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
