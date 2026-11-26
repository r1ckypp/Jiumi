# 参与啾咪开发

[English](../CONTRIBUTING.md) · **简体中文**

第一次贡献可以很小：改清楚一句译文，做一只展示某个缺失动作的示例宠物，或者为你日常使用的工具写一个适配器。请说明你希望宠物做什么，以及别人如何在自己的电脑上看到结果。

## 构建本地版本

准备 Node.js 20 或更高版本、npm 10 或更高版本，以及 Python 3。在仓库根目录运行：

```sh
npm ci
npm run build
node tests/event_feedback.cjs
```

打开 `dist/maker.html`，制作一只宠物，并在断网时打开导出的 HTML。制作器的 TypeScript 源码在 `src/`，修改后重新构建并同步仓库里的浏览器产物。专注计时器源码在 `examples/focus-timer/index.ts`，同一条构建命令也会重新生成模块 JSON。

## 按改动选择检查

浏览器测试使用 Python Playwright 和 Google Chrome。在虚拟环境中运行 `python3 -m pip install playwright`，并使用已安装 Chrome 的电脑。从仓库根目录运行测试。

| 改动范围 | 验证命令 |
| --- | --- |
| 事件、优先级或打断 | `node tests/event_feedback.cjs` |
| 制作器、PNG 动作帧或 HTML 导出 | `python3 tests/offline_maker.py` |
| 插件导入、生命周期或持久状态 | `python3 tests/offline_modules.py` |
| 本机 Hook 和 Unix 套接字 | 在 macOS 上运行 `python3 tests/event_bridge.py` |
| macOS 悬浮应用 | 在有 Swift 命令行工具和图形会话的 macOS 上运行 `python3 tests/desktop_bundle.py` |

## 报告问题或提交改动

- 报告问题时，请写明宿主、操作系统、浏览器或运行时版本，以及能复现问题的最少步骤。写清预期与实际结果。动画问题最好附一个使用可公开素材的最小角色包。
- 建议新插件或适配器时，请描述输入事件、所需能力、可见反馈和断网时的行为。修改角色包格式时，说明旧宠物如何继续打开。
- 每个拉取请求集中处理相关改动，说明用户能看到什么变化、关联已有议题，并列出实际运行过的检查。视觉改动可附前后对照帧或短录屏。
- 示例素材和模块依赖应允许再分发，请注明来源和授权。提交原创作品或你有权按本仓库许可证提交的内容。

## 翻译与评审

项目入口和社区文档的简体中文版放在 `docs/zh-CN/`。英文和中文 Skill 分别在 `skill/jiumi-pet/` 和 `skill/jiumi-pet-zh/` 维护说明与操作指南。设计规范统一用英文写在 `docs/spec/`。行为变更请同步相关规范、两种语言的使用说明和示例。工具名、文件名、协议字段及命令保持原样。欢迎用中文或英文提交小修正和问题报告。

请尊重不同意见，保护他人隐私，让反馈聚焦具体工作。参见[社区行为规范](CODE_OF_CONDUCT.zh-CN.md)及[安全问题私下报告指南](SECURITY.zh-CN.md)。

## 提交和拉取请求的标题

维护者、外部贡献者和 Agent 每次提交或发起拉取请求时，都使用英文标题，格式为 `type(scope): summary`。范围选最主要的模块，用小写字母、数字和连字符表示。摘要用简短的动词短语写清一项具体改动。动机和取舍放在正文。遇到破坏性变更，使用 `type(scope)!: summary`，并在正文的 `BREAKING CHANGE:` 段落写明迁移方式。

| 类型 | 用途 |
| --- | --- |
| `feat`、`fix` | 添加能力或修复缺陷 |
| `docs`、`test` | 修改文档或测试 |
| `refactor`、`perf` | 调整内部结构或改进性能 |
| `build`、`ci`、`chore` | 打包、自动化或仓库维护 |
| `revert` | 撤销改动，正文注明原提交 |

例如，切换语言时保留宠物名字可写成 `fix(maker): keep the pet name when switching languages`。新增落地动作可写成 `feat(player): animate landing after a drag`。补充素材导入说明可写成 `docs(skill): explain how to import custom artwork`。其他常用范围包括 `desktop`、`plugins`、`events` 和 `repo`。压缩合并时由 GitHub 添加拉取请求编号。

## 从议题到合并

1. 先搜索已打开和已关闭的议题、拉取请求。遇到相同问题，在原帖补充证据。新问题可选中英文缺陷或功能建议表单。缺陷标题写出操作和症状，例如「拖动桌宠后会话提醒消失」。建议标题写出希望增加的能力，例如「允许计时器插件播放自定义动作」。建议新能力时，说明用户怎样使用，以及怎样判断它已实现。独立的小修复和翻译可以直接发起拉取请求。修改公共协议或新增平台支持时，先讨论设计再投入开发。
2. 在自己的分支仓库或本地检出目录中，从最新的 `main` 创建分支。每次提交解决一个问题，向 `main` 发起拉取请求。正文用 `Refs #123` 引用相关议题，合并即可解决时使用 `Closes #123`。
3. 写清问题、改动、实际运行的检查与观察结果，注明尚未验证的宿主。外观改动附截图，动作或时序改动附短录屏。影响已有宠物或插件时说明兼容性和迁移步骤。贡献者对提交内容负责，包括通过 Agent 生成的部分。
4. 评审者核对实际行为、相关测试、兼容性、素材授权及双语文档。维护者用 `bug` 标记确认的缺陷，用 `enhancement` 标记功能建议。关闭重复报告时链接原议题，需要更多证据时说明希望补充哪一步或哪项结果。
5. 在原分支回应评审。维护者核对最终标题和验证证据，以拉取请求标题执行压缩合并。每个合并的拉取请求在 `main` 历史中对应一个提交。拉取请求在创建、修改标题或推送新提交时，会自动检查标题格式。

[新建议题](https://github.com/r1ckypp/jiumi/issues/new/choose) · [浏览拉取请求](https://github.com/r1ckypp/jiumi/pulls)
