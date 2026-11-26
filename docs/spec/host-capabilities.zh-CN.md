# 宿主能力与会话提醒

[English](host-capabilities.md) · **简体中文**

适配器用 v1 事件报告事实，插件请求反馈，宿主负责呈现和执行用户操作。角色包携带插件定义。会话地址、待处理请求、凭据和设备授权留在本机。

## 身体与气泡

身体仍由交互状态机管理。独立的会话气泡在同一播放器内经历抚摸、拖动、落地和显隐后保留。提醒按插件 ID、来源和会话 ID 区分，同时只显示最新一条，处理后露出上一条。其他会话结束不会清除当前提醒。断开来源时清理该来源的提醒，卸载播放器时清理全部。最多保留 32 条。

## 插件契约

在制作器导入 examples/agent-confirm.json，或在 pet.py create 时通过 --module 启用。session-notice 声明出现事件 show、清除事件 clear、标题 title 和操作 action。示例收到 agent.input_requested 时显示，收到同一来源、同一会话的 agent.started、agent.resumed、agent.completed 或 agent.closed 时撤下。适配器可以提供不超过 160 字符的纯文本 summary。用户点击后才请求 session.open，点击本身不会代替用户批准 Agent 的操作。

mountPet 第四个参数可以提供 session(method,{source,session})，同步或异步返回布尔值。播放器先查询 available，有能力时才显示按钮。点击调用 open，随后在角色元素派发 pet.action，包含 action、source、session、ok。成功表示系统接受了打开请求。宿主还可实现 layout(visible) 调整窗口。跳转目标来自设备绑定，事件和插件包均无权设置它。

## 本机使用

macOS 上先用已知会话地址绑定目标，再启动监听。地址支持可信 HTTPS 会话链接或客户端的 scheme://threads/会话UUID 深链接。重复绑定会更新地址。监听和绑定使用同一只宠物、同一本地库。已有 Claude Hook 可直接触发，也能由其他适配器通过标准输入发送 v1 事件。

```sh
python3 agent_events.py bind "$PET_ID" "$SOURCE" "$SESSION" "$CONVERSATION_URL"
python3 agent_events.py watch "$PET_ID"
# 在另一个终端发送同一来源、同一会话的事件
python3 agent_events.py emit "$PET_ID" < event.json
```

单文件 HTML 无需服务。打开导出的桌宠，点「试用会话提醒」，拖动宠物，再点「结束示例提醒」。示例只在当前页面运行。集成宿主可以用 stage.feedback.dispatch(event) 输入真实事件。缺少会话跳转能力时，页面保留摘要和来源、会话标识，供用户手动返回。

## 后续方向

菜单、声音和系统通知可沿用相同的能力查询机制。跨通道演出可扩展有时限、可由用户手势撤销的占用。联网服务和跨设备投递由可选集成提供。当前示例实现气泡与用户点击返回会话。
