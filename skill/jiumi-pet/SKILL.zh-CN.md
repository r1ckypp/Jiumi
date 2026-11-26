---
name: jiumi-pet
description: 使用预设或自带 PNG 在本机制作桌宠，离线预览、抚摸、拖动并导出单文件 HTML。
---

# 创建啾咪桌宠
[English](SKILL.md) · **简体中文**


按用户的角色描述直接制作。没有特别说明就生成奶油黄方糖小鸡；指定动物时使用对应预设，例如蓝色小猪用 `--animal pig`。只有用户指定配色时才传 `--color`。常规角色自动套用预对齐的活动部件，直接交付，无需用户选型或调关节。

运行 `python3 pet.py create "名字" --output "交付目录"`。提供 HTML 预览，macOS 同时提供对应应用；提示双击应用启动悬浮桌宠，从菜单栏爪印管理显隐和设置。明确只要 HTML 时加 `--html-only`。已有用户原画用 `--image` 保留。

当动作需要人形关节联动、特定部件素材或独立表演片段时，才读取[进阶动作制作](references/articulation.zh-CN.md)。由 Agent 根据动作推断制作方式，只有影响成品的创作取舍确实不清楚时再询问。

需要本机导入、启动桌宠、安装插件或监听事件时，按需读取[本地操作指南](references/workflows.zh-CN.md)。
