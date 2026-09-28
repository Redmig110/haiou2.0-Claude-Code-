# 海鸥 2.0 — DSH 适配

DSH 原生会读取 DSH_HOME/AGENTS.md。安装器使用可重复运行的标记块，不改 DSH 安装目录、profile、node_modules 或现有 prompt-inject.md。

安装：

    powershell -ExecutionPolicy Bypass -File .\dsh-files\install.ps1

默认目标为当前用户目录下的 .dsh。设置 DSH_HOME 时会自动使用自定义目录。

检测到 dsh-purge 时，插件可能优先使用 prompt-inject.md 决定人格。安装器会报告冲突，但不会覆盖现有 prompt-inject.md，避免破坏用户已有的自定义提示。

卸载：

    powershell -ExecutionPolicy Bypass -File .\dsh-files\uninstall.ps1
