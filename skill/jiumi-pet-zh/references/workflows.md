# 本地操作指南

## 制作与保存

打开随包的 `maker.html`，选择角色或导入透明 PNG，起名后试试抚摸和长按拖动。「生成桌宠 HTML」导出可直接打开的成品；「导出角色包」保存可移交给另一个助手继续编辑的 JSON。编辑时沿用同一 UUID。

从 Skill 目录运行以下命令，将角色包导入本机库。用 import 返回的 UUID 替换 PET_ID。

```sh
python3 pet.py import pet.json
python3 pet.py local
python3 pet.py preview PET_ID
```

要启动 macOS 悬浮窗，运行 `python3 pet.py open PET_ID`。用菜单栏爪印管理显隐与设置。要交付独立应用，运行 `python3 pet.py desktop-app PET_ID OUTPUT_DIRECTORY`。

## 动作与插件

在「动作帧」里选择动作，导入按播放顺序编号的透明 PNG。用 `held` 表示拎起，用 `landing` 表示落地。形象、脚底和部件锚点应对齐；只覆盖需要更换的动作。大型动作库可在 `motionPools.working` 配置多个候选。

在「本地插件」中导入随包的 `examples/focus-timer.json`，勾选以启用。复制 `examples/pickup.json` 可以编写可复用的交互状态机。创建角色时也可用 `--module examples/agent-confirm.json` 加入会话提醒。

用户明确需要监听时，macOS 上用 `python3 agent_events.py watch PET_ID` 启动本机桥接。在用户选择的项目中配置 Claude Code hook 调用 `python3 /绝对路径/agent_events.py claude PET_ID`。其他宿主可通过播放器的 dispatch 方法传入 v1 事件。事件格式和会话绑定详见英文[事件规范](https://github.com/r1ckypp/jiumi/blob/main/docs/spec/event-feedback.md)和[宿主能力规范](https://github.com/r1ckypp/jiumi/blob/main/docs/spec/host-capabilities.md)。
