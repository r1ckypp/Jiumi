# 本地操作指南

## 制作与保存

打开随包的 `maker.html`，选择角色或导入透明 PNG，起名后试试抚摸和长按拖动。「生成桌宠 HTML」导出可直接打开的成品；「导出角色包」保存可移交给另一个助手继续编辑的 JSON。编辑时沿用同一 UUID。

从 Skill 目录运行以下命令，将角色包导入本机库。用 import 返回的 UUID 替换 PET_ID。

```sh
python3 pet.py import pet.json
python3 pet.py local
python3 pet.py preview PET_ID
```

要启动 macOS 或 Windows 悬浮窗，运行 `python3 pet.py open PET_ID`。用 Mac 菜单栏或 Windows 通知区域图标管理显隐与设置。要交付独立应用，运行 `python3 pet.py desktop-app PET_ID OUTPUT_DIRECTORY`。

已有角色打包失败时，沿用原角色 JSON 和预览。如果只剩本机角色库，运行 `python3 pet.py preview 角色UUID` 打开该角色的制作页，从中导出角色 JSON 和 HTML。Windows 上找不到 `dotnet` 表示构建工具无法调用 .NET SDK，所需版本见桌面客户端规范。

## 动作与插件

在「动作帧」里选择动作，导入按播放顺序编号的透明 PNG。用 `held` 表示拎起，用 `landing` 表示落地。形象、脚底和部件锚点应对齐；只覆盖需要更换的动作。大型动作库可在 `motionPools.working` 配置多个候选。

给已有桌宠加插件时，先核对已安装模块和当前启用项。社区插件用远程 MCP 的 get_community_module 取得用户选定 ID 和版本的完整 JSON，再用本地 install_pet_module 或 `python3 pet.py install-module 角色UUID module.json --module-id ID --version N` 安装。随包模块直接使用本地 JSON 和文件中声明的版本。缺少动作时用 `--clips clips.json` 传入动作名到动作定义的映射，保留已有动作和其他插件的关闭状态。打开返回的预览，导出更新后的角色。桌面设置与陪打字详见[桌面客户端规范](desktop-client.md)。

制作陪打字动作时，从同一角色生成两张对齐的透明 PNG，一张左翼下落，一张右翼下落，身体和画布保持一致。clips.json 的键取缺少的动作名（`type-left` 或 `type-right`），每个动作包含 `frames`（PNG data URL 数组）、`frameMs`（例如 100）及 `loop: false`。每侧一帧即可。安装随包 v2 模块用 `python3 pet.py install-module 角色UUID examples/typing.json --module-id typing --version 2 --clips clips.json`。

在「本地插件」中导入随包的 `examples/focus-timer.json`，勾选以启用。复制 `examples/pickup.json` 可以编写可复用的交互状态机。创建角色时也可用 `--module examples/agent-confirm.json` 加入会话提醒。

用户明确需要监听时，macOS 上用 `python3 agent_events.py watch PET_ID` 启动本机桥接。在用户选择的项目中配置 Claude Code hook 调用 `python3 /绝对路径/agent_events.py claude PET_ID`。其他宿主可通过播放器的 dispatch 方法传入 v1 事件。事件格式和会话绑定详见英文[事件规范](https://github.com/r1ckypp/jiumi/blob/main/docs/spec/event-feedback.md)和[宿主能力规范](https://github.com/r1ckypp/jiumi/blob/main/docs/spec/host-capabilities.md)。
