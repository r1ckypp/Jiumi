---
name: jiumi-pet-zh
description: 在本机创建或修改 Jiumi 桌宠。适用于从描述或 PNG 制作角色、为已有角色添加动作或插件，以及交付离线 HTML 试玩或 macOS、Windows 桌面客户端。
---

# 制作或修改 Jiumi 桌宠

先确定要操作的角色，再选择交付形式。从解压后的 Skill 目录运行命令；Windows 可将 `python3` 换成 `python`。从源码使用时，先在仓库根目录运行 `python3 integrations/local/build.py`，再解压对应语言的 Skill 包。

| 用户要做什么 | 从哪里开始 |
| --- | --- |
| 新建角色 | 用 `python3 pet.py create "角色名" --language zh-CN --output "交付目录"`。用户给了原画就加 `--image "原画.png"`；未指定形象时用奶油黄方糖小鸡。指定动物用对应预设，明确指定配色时才传 `--color`。 |
| 修改已有角色或安装插件 | 用 `python3 pet.py local` 找到已有 UUID，或导入用户指定的角色包。检查当前素材、动作和插件启停选择，只改用户要求的部分。沿用 UUID 和已保存的语言。见[本地操作指南](references/workflows.md)。 |
| 只要 HTML 试玩 | 新建时加 `--html-only`；已有角色从制作器导出。创建命令返回制作预览页；用「生成桌宠 HTML」导出独立播放器，离线打开核对原画和互动。 |
| 交付桌面客户端 | 新建命令在 macOS 和 Windows 上默认还会尝试构建客户端。已有角色用 `python3 pet.py desktop-app 角色UUID "交付目录"`。 |

新建时按制作请求的语言传 `--language zh-CN` 或 `--language en`，明确指定的界面语言优先。客户端在应用名、系统权限、登录项和设置中统一叫 Jiumi。角色名只用于角色。只有用户明确给客户端命名时才覆盖 Jiumi。

## 桌面交付与回退

优先用项目模板在用户机器上构建。先核对目标平台与构建机。模板按当前系统选择宿主，Mac 生成 macOS 应用，Windows 电脑生成 Windows 目录。Mac 交付可打开的应用；Windows 交付含 Jiumi.exe 的完整 Jiumi-Windows 目录。打开对应客户端，检查是用户的角色、所需互动可用。

- 若创建命令返回 `desktop_error`，已生成的角色和 HTML 仍然可用。保留返回的 UUID 和预览，修复具体问题后只重试 `desktop-app`。
- 若本机没有 Python，可直接打开安装包里的 `maker.html`，在页面中选定请求所用的界面语言，再导入 PNG、导出角色 JSON 和 HTML。编辑已有角色时使用它的制作页面。手头只有角色 JSON 时保留原包，交给支持导入的工具继续。
- 若本机仍无法构建目标客户端，说明具体原因，到[官方 GitHub Releases](https://github.com/r1ckypp/Jiumi/releases) 核对系统、架构及该版本载入本地角色包的方式。有兼容附件时提示用户下载，再结合用户素材在本机组装并打开验证。无法核实兼容版本、载入方式或运行结果时，交付已有角色与可用预览，明确桌面部分尚待完成或验证。

普通角色使用预对齐部件。涉及关节联动、自定义分件或独立动作帧时，查[进阶动作制作](references/articulation.md)。制作桌面客户端、互动插件或调整设置时，查[桌面客户端规范](references/desktop-client.md)。
