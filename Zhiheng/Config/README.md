# 构建配置说明

`Base.xcconfig` 只保存可以公开提交的非敏感构建设置。Xcode 的 Debug 和 Release 配置都读取它；没有本地私密文件时，工程仍必须能够正常构建。

需要经过任务批准的本地覆盖值时：

1. 将 `Secrets.xcconfig.example` 复制为同目录下的 `Secrets.xcconfig`。
2. 只在 `Secrets.xcconfig` 中填写本机开发值。
3. 提交前确认 `Secrets.xcconfig` 仍被根目录 `.gitignore` 忽略。

不得把 DeepSeek、OpenAI 或其他 AI 厂商的正式 API Key 放入任何 iPhone 构建配置、Info.plist 或源码。个人 Debug 真机允许用户在 App 内主动输入 DeepSeek 密钥并保存到该设备的 Keychain，密钥不会进入构建配置或安装包；Debug 模拟器在未保存密钥时仍可连接本机 `127.0.0.1:8787` 代理。Release 版本不启用个人直连，正式分发必须配置经过鉴权与限流的 HTTPS 后端。
