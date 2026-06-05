# AI 验证说明

本项目通过游戏内“设置 - AI设置”选择服务商、模型和 API Key，不再读取 `.env`、`env` 或 `env.example`。

## 设置入口

1. 打开游戏设置界面。
2. 在“服务商”中选择国内、国外或本地模型提供方。
3. 在“AI Model”中选择官方模型列表中的模型。
4. 云端服务填写 API Key；Ollama 本地服务无需填写 API Key。
5. Ollama 可在“本地模型”中输入已通过 `ollama pull` 下载的模型名，例如 `qwen2.5:7b-instruct`。

服务商配置来自 `res://config/ai_providers.json`。普通玩家不需要手动填写 Base URL。

## 手动验证流程

1. 使用 Godot 4.6.2 打开项目。
2. 在设置页选择一个 provider 和模型。
3. 启动新游戏，确认第一次 AI 响应会通过 `commands` 驱动背景、角色、对白等场景元素。
4. 切换到 Ollama，确认本地模型使用 `http://localhost:11434/v1/chat/completions`。
5. 点击选项后，确认对话历史中出现“玩家”选择，并且下一轮 AI 能承接该选项。
6. 模拟包含 `[jump_up]`、`[bounce]` 或孤立 `[/color]` 的 AI 返回，确认 UI 不显示异常标签。

## 静态检查

以后提交 AI 相关改动前，建议运行：

```powershell
git diff -- scripts/managers/ai_manager.gd scripts/managers/script_engine.gd scripts/managers/dialogue_manager.gd scripts/scenes/settings_ui.gd
Select-String -Path scripts/managers/ai_manager.gd -Pattern "CharacterManager|BackgroundManager|AudioManager|ParticleManager|CGManager|UIManager|GameManager"
Select-String -Path config/ai_providers.json -Pattern "openai|kimi|ollama"
```

如果 Godot 已加入 `PATH`，也可以运行当前 Godot 版本对应的无头导入或脚本检查命令。
