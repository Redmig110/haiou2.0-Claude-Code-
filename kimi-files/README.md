# 海鸥 2.0 — Kimi 原生适配

此目录包含一个同时兼容 Kimi Work 和 Kimi Code 的原生插件。

- system-prompt.md 只有 18 KB，低于单字段 32 KB 限制。
- skills/seagull-2/SKILL.md 保存完整 CLAUDE.md 和原始 few-shot 示例，没有删减。
- sessionStart.skill 在每个新会话自动加载完整技能。
- 不替换 Kimi 原生系统提示、工具、权限、Skills 或其他插件。
- Kimi Work 使用官方 prompts.systemPromptOverride 替换默认提示组合；动态上下文、工具和权限保持不变，且只影响新会话。

Windows 安装：

    powershell -ExecutionPolicy Bypass -File .\kimi-files\install.ps1

脚本会安装到 Kimi Code，并登记、安装到普通 Kimi Desktop 的 Kimi Work 运行时，同时启用完整 systemPromptOverride。两端都需要新建会话；Kimi Code 还需重启应用或执行 /plugins reload。

Windows 安装器会在当前用户 Startup 目录创建 SeaGull-Kimi-Override.cmd，并启动隐藏 watcher。它监控 Daimon 控制端点，只在 Kimi Desktop 进程重启后自动重放 systemPromptOverride。卸载器会先停止 watcher、删除启动项，再恢复默认提示。

非标准安装位置可传入 -DaimonCli、-NodeBin、-KimiShareDir 和 -KimiCodeHome 参数。安装和卸载均支持 -SkipKimiWork / -SkipKimiCode。卸载 Kimi Work 时需要先启动 Kimi Desktop，使本地控制端点可用。

普通 Chat 与 Kimi Work 是不同运行模式。普通 Chat 不支持全局 systemPromptPath；如需在 Chat 使用，请创建“海鸥”项目，并把 system-prompt.md 内容放入项目指令。

卸载：

    powershell -ExecutionPolicy Bypass -File .\kimi-files\uninstall.ps1

插件详情链接：kimi-work://plugin?id=seagull-2
