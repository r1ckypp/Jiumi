# 桌宠事件与反馈 v1

[English](event-feedback.md) · **简体中文**

## 运行边界

单文件 HTML 内嵌纯 JavaScript 调度器。普通网页、试衣间、离线桌宠及原生窗口使用同一个 mountPet。原生桥接仅由用户主动运行 watch 时启用。一个监听进程绑定一个本机角色；角色 ID 和运行实例通过专属套接字与独占锁确定。可移植角色包保存角色、动作映射和选用的插件，不保存设备绑定、事件流或权限。

## 接口

mountPet 返回控制器。dispatch(event) 输入事实，getState() 读取当前汇总状态，disconnect(source) 清除来源会话，setVisible(false) 停止身体动画，dispose() 释放实例。play(name) 用于本地试播。适配器可发送自定义类型，由已启用规则消费。新增持续交互可在插件中声明转移表及优先级；普通一次性反馈无需修改状态机。

事件示例：
```json
{"v":1,"id":"req-42","source":"editor","session":"session-a","type":"agent.input_requested","at":1780000000000}
```
at 为 Unix 毫秒。外部来源、事件 ID、类型和会话标识每项最多 160 字符。来源与事件 ID 联合去重，保留最近 1024 项。同一会话按事件时间排序；同毫秒按到达顺序。适配器应复用上游稳定 ID。Claude 示例对每次 Hook 调用生成 ID，另由状态边沿抑制连续重复通知。此设计用于即时反馈，不提供可计费的恰好一次交付。

## 状态、规则与打断

| 输入 | 会话转换 | 默认瞬时反馈 |
| --- | --- | --- |
| agent.started / agent.resumed | working | 无 |
| agent.input_requested | waiting | attention |
| agent.completed | ended | celebrate |
| agent.closed | ended | 无 |
| pet.tap | 无 | affection |

每个来源、会话独立。汇总顺序 waiting、working、idle。结束记录短时保留以挡住旧事件。状态重复上报可续期，但不再触发边沿反馈。五分钟无新消息的会话在 tick、下一事件或显示恢复时过期。长期任务的来源应定期报告最新状态。15 秒前的事件仍可重建有效状态，不补播瞬时反馈；超过五分钟或超前超过五秒的事件丢弃。首次接入不会查询历史会话。

规则沿用 catalog 与 pet.plugins。同一事件的自定义身体意图覆盖默认意图。可以同时启用粒子规则，例如现有桃花雨。身体意图优先级为试播、affection、attention、celebrate；低优先级瞬时请求直接合并丢弃，持续状态仍更新。每次打断递增版本，过期动画回调不会抢回身体。动作完成重新读取当前状态。标签页隐藏时接收状态变化，停止播放，重新显示后恢复。减少动态效果设置下不播粒子和身体运动。

```json
{"id":"focus-finished","version":1,"name":"专注完成","on":"timer.finished","intent":"celebrate"}
```

角色可在 appearance.motions 中将意图映射为已有动作，如 {"attention":"greet"}。不支持的映射应回落到通用动作。新增眼睛或头羽的局部动作需要相应图层；可在渲染器扩展，适配器及规则无需变化。

## 第一个外部适配器

macOS 执行 `python3 agent_events.py watch 宠物UUID`，会启动一个接收事件的窗口。退出监听进程会关闭它启动的窗口。Claude Code 项目设置中的 hooks 条目可按以下方式配置（绝对路径换成本机路径）。每种需要监听的事件添加对应条目，保留已有设置：

```json
{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"python3 '/绝对路径/agent_events.py' claude 宠物UUID"}]}]}}
```

支持 UserPromptSubmit、PreToolUse、PermissionRequest、Stop 和 SessionEnd。PermissionRequest 表示等待，PreToolUse 表示开始或恢复执行；Stop 只说明该轮结束，庆祝是默认表现，不表示代码测试通过。忽略 SubagentStop。仅提取事件名及 session_id，不转发命令、对话或文件路径，不返回审批决定。将适配器配置在希望绑定的项目；停用时移除自己的 Hook 条目并结束监听。套接字位于当前用户私有目录。使用非阻塞数据报，监听器离线时丢弃观测，不重放。外部客户端可按此协议编写自己的适配器。

## 验收与边界

用可控时钟和模拟播放器重放“工作 → 等待 → 摸摸 → 仍等待 → 恢复工作 → 完成”。并发会话独立，重复、过时和隐藏期间的事件不会连播。另测自定义来源驱动插件规则。纯 H5 不监听操作系统。首版不包含跨设备实时传输、Windows 原生监听、日志采集、监控指标看板或通用规则编程语言。

交互状态机与助手会话状态并行。转移表接收 pet.grab、pet.release 和 pet.cancel。抓取期间由 held 接管身体；松手后 landing 播放一次，再恢复最新会话状态。落地时可再次抓起，取消手势直接恢复。可提供循环 clips.held 和单次 clips.landing 表现专属姿势，缺帧时使用内置动效。这些转移由随包的拎起插件声明；打断与恢复规则见[插件 SDK](plugin-sdk.zh-CN.md)。
