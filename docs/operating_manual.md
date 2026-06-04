# 《最南幻想》操作手册

## 1. 系统要求

| 项目     | 最低配置                                      | 推荐配置                                  |
| :------- | :-------------------------------------------- | :---------------------------------------- |
| 操作系统 | Windows 10 (64-bit) / macOS 11 / Ubuntu 20.04 | Windows 11 / macOS 13 / Ubuntu 22.04      |
| 处理器   | Intel i5-7200U / AMD Ryzen 3 1200             | Intel i5-10400 / AMD Ryzen 5 3600         |
| 内存     | 4 GB RAM                                      | 8 GB RAM                                  |
| 显卡     | 支持 OpenGL 3.3 的集成显卡                    | 支持 Vulkan 1.2 的独立显卡                |
| 存储空间 | 500 MB 可用                                   | 1 GB 可用                                 |
| AI 服务  | 无需额外配置（可使用云端 API）                | 安装 Ollama，并下载 `qwen2.5:7b-instruct` |

## 2. 安装与启动

1. 从 GitHub Releases 或大赛官网下载对应平台的压缩包。
2. 解压到任意目录。
3. **首次开始游戏前，务必先配置 AI 服务（见第3节）**。
4. 双击 `最南幻想.exe` 启动游戏。

## 3. AI 设置详解（必读）

游戏剧情完全由 AI 生成，因此正确配置 AI 是游玩的前提。
在**主菜单**点击**「游戏设置 → AI设置」**，你将看到三个输入框：

- **Base URL**：AI 服务的地址。
  - 本地 Ollama：`http://localhost:11434/v1`
  - 云端 API：例如 `https://api.deepseek.com/v1`
- **Model**：模型名称。
  - 本地 Ollama：`qwen2.5:7b-instruct`
  - 云端 API：例如 `deepseek-chat`
- **API Key**：云端 API 的密钥，本地 Ollama 可留空。
- **Ollama一键部署**：点击该按钮，游戏将会**自动为你一键部署并运行本地Ollama模型**。

### 🌟 一键部署本地 AI

1. 解压后，游戏目录下有一个 `deploy_ollama.bat` 脚本。
2. 双击运行该脚本，它会自动安装 Ollama、启动服务并下载千问模型。
3. 你也可以在游戏设置里点击**「Ollama一键部署」**按钮来启动。
4. 部署完成后，Base URL 保持默认的 `http://localhost:11434/v1`，Model 选择 `qwen2.5:7b-instruct` 即可。

### ☁️ 使用云端 API

- 在 AI 设置中填入你的 Base URL、Model 和 API Key，点击任意位置即自动保存。
- 请妥善保管你的 API Key，不要泄露给他人。

## 4. 基本操作

| 操作            | 说明                                          |
| :-------------- | :-------------------------------------------- |
| **推进对话**    | 鼠标左键 / 空格键 / 回车键                    |
| **选择选项**    | 鼠标左键点击选项按钮                          |
| **好感度面板**  | 鼠标右键 / A 键                               |
| **快速读档**    | 点击 HUD 上的「快速读档」按钮                 |
| **自动模式**    | 点击「自动」按钮，文本显示完后自动前进        |
| **快进模式**    | 点击「快进」按钮，长对话1秒跳过，普通对话加速 |
| **存档 / 读档** | 点击右上角对应按钮，支持多页槽位管理          |
| **返回主界面**  | 点击「主界面」按钮，可保存进度                |
| **设置**        | 调节音量、文本速度、AI 连接等                 |

## 5. 存档位置

- **Windows**: `%APPDATA%\Godot\app_userdata\nju_dream\saves\`
- **macOS**: `~/Library/Application Support/Godot/app_userdata/nju_dream/saves/`
- **Linux**: `~/.local/share/godot/app_userdata/nju_dream/saves/`

## 6. 常见问题

**Q: 游戏打开后黑屏？**
A: 请更新显卡驱动，并确认系统满足最低配置。

**Q: AI 无响应或显示“AI 暂时不可用”？**
A:

- 本地 Ollama：确保服务已启动（终端执行 `ollama serve`），模型已下载（`ollama list` 检查）。
- 云端 API：检查 Base URL、Model、API Key 是否正确，网络是否连通。
- 可尝试在设置中更换 AI 地址或模型。

**Q: 存档无法读取？**
A: 不同版本间的存档可能不兼容，请使用与存档时相同的游戏版本。

**Q: 按钮音效不响？**
A: 在设置界面中确认“按钮音效”已开启，且 SFX 音量不为零。
