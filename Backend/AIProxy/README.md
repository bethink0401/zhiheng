# 知衡 AI 开发代理

该代理只用于开发阶段验证真实模型调用。iPhone App 不保存 DeepSeek API Key；代理从进程环境读取密钥，并只转发 App 已聚合的 `HealthFactPack`。当前使用 DeepSeek Responses API 与 `deepseek-v4-flash`。

## 启动

在终端中先设置本人的开发密钥，再启动代理：

```bash
export DEEPSEEK_API_KEY='在本机终端填写，不要写入文件或聊天'
python3 Backend/AIProxy/server.py
```

默认监听 `127.0.0.1:8787`，只供本机 iOS 模拟器访问。App 的 Debug 构建默认请求：

```text
http://127.0.0.1:8787/v1/health-assistant/respond
```

可通过 Xcode Scheme 环境变量 `ZHIHENG_AI_PROXY_URL` 改为已部署的 HTTPS 代理地址。正式分发必须使用具备鉴权、限流、审计和密钥轮换的 HTTPS 后端，不能把本开发代理直接暴露到公网。

个人 Debug 真机不使用本代理：用户在 App“我的”页面主动输入 DeepSeek 密钥，密钥存入该设备的 Keychain，并由 Debug 版直接通过 HTTPS 调用 DeepSeek。Release 版不启用个人直连，仍必须使用正式后端代理。

如果此前按照旧说明把 DeepSeek 密钥放在 `OPENAI_API_KEY` 中，代理暂时兼容该变量；建议改为语义明确的 `DEEPSEEK_API_KEY`。两者都只允许存在于代理进程环境中。

响应兼容层只检查客户端能否解码所需的 JSON 字段和类型，不评价、纠正或重写 DeepSeek 的普通结论。当前唯一针对实测供应商差异的转换，是把偶发的 `uncertainty` 字符串数组连接为客户端模型要求的单个字符串。医疗安全和事实引用边界由 App 内独立规则承担。

## 验证

```bash
cd Backend/AIProxy
python3 -m unittest -v
```

代理日志不记录问题正文、健康事实包、响应正文或授权头。
