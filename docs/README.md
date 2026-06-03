<div align="center">
  <h1>最南幻想</h1>
  <p><strong>AI 情感陪伴 Galgame · 南京大学校园主题</strong></p>
  <p>
	<a href="https://github.com/QigChenm/GuTeamGame/releases"><img src="https://img.shields.io/badge/下载-Windows-blue?logo=windows" alt="Windows"></a>
	<a href="https://github.com/QigChenm/GuTeamGame/releases"><img src="https://img.shields.io/badge/下载-macOS-silver?logo=apple" alt="macOS"></a>
	<a href="https://github.com/QigChenm/GuTeamGame/blob/main/docs/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
    <a href="https://qigchenm.github.io/GuTeamGame"><img src="https://img.shields.io/badge/项目网站-最南幻想-ff69b4?logo=google-chrome" alt="Website"></a>
  </p>
</div>





## 一、项目简介

**最南幻想** 是一款基于 Godot 4 引擎开发的 AI 驱动 Galgame，专为大学生群体设计。游戏以南大鼓楼校区为背景，通过大语言模型实时生成对话与剧情，提供个性化、沉浸式的情感陪伴体验。玩家可以与 AI 角色进行多轮对话、触发分支剧情、解锁精美 CG 和音乐，在春去冬来的季节流转中感受温暖与感动。

## 二、核心特色

- **全 AI 叙事**：游戏内所有剧情均由 AI 实时生成，无预设剧本，玩家的每次选择都能得到即时、连贯的反馈。
- **双重 AI 模式**：支持本地 Ollama 模型（低延迟、无网络）和云端 API（高智能、免部署），可灵活切换。
- **沉浸式演出**：角色拥有丰富的表情、动作、入场动画；支持背景切换、粒子天气、CG 动画、多声道音频系统。
- **完整的 Galgame 系统**：包含设置、存档、读档、对话历史、好感度、鉴赏模式（CG/音乐）、自动/快进模式等商业级功能。
- **校园心理关怀**：剧情设计融入正向情感引导，帮助玩家缓解压力、提升心理韧性。

## 三、快速开始

### 1. 下载与运行
- 前往 [Releases 页面](https://github.com/你的用户名/你的仓库名/releases) 下载对应平台的最新版本压缩包。
- 解压后直接运行 `最南幻想.exe` (Windows) 或 `最南幻想.app` (macOS)。

### 2. 配置 AI 服务
#### 使用本地 Ollama（推荐）
1. 安装 [Ollama](https://ollama.com)。
2. 下载模型：`ollama pull qwen2.5:7b-instruct`。
3. 启动 Ollama 服务：`ollama serve`。
4. 运行游戏，AI 将默认自动连接本地服务。
5. 本地模型可以在游戏设置 > AI设置里面查看和更改。

#### 使用云端 API
如果您不想使用本地AI模型，我们提供了另外的方法：

1. 启动游戏前，请先配置好您的云端API。
1. 开始游戏前，请先前往游戏设置 > AI设置界面填写您使用的Base URL、Model 和 API 密钥。
1. 游戏将自动保存您的修改，后续您也可以打开设置进行改动。

### 3. 操作说明
- **鼠标点击 / 空格键**：推进对话
- **鼠标左键**：选择选项
- **鼠标右键**：打开好感度面板
- **A 键**：切换好感度面板
- **HUD 按钮**：存档、读档、设置、自动模式等

## 四、项目结构

```text
res://
├── scenes/ # 场景文件
├── scripts/ # 核心脚本
| ├── datatypes/ # 自定义资源文件类型
│ ├── managers/ # 自动加载单例（GameManager, AIManager, ScriptEngine等）
│ ├── plugins/ # 辅助插件
│ └── scenes/ # 场景挂载脚本（DialogueScene等）
├── assets/ # 资源文件（图片、音频、字体等）
├── config/ # 配置文件（game_settings.json等）
├── docs/ # 说明文档，含README和游戏操作手册等
└── project.godot # Godot 项目文件
```

## 五、技术栈

- **游戏引擎**：Godot 4.6.2 (GDScript)
- **AI 接口**：Ollama / 云端 API (HTTP)
- **指令体系**：自定义 JSON DSL 命令流
- **数据存储**：本地 JSON 文件存档 + ConfigFile
- **音频系统**：AudioServer 多总线管理

## 六、贡献者

| 成员   | 职责                                   |
| ------ | -------------------------------------- |
| 赵卿成 | 项目负责人、核心框架开发、游戏系统设计 |
| 俞天镒 | AI 模块对接、提示词工程、本地模型部署  |
| 汤艺暄 | 美术设计（角色立绘、背景、UI）         |
| 卞涵砚 | 音频资源制作、剧情测试、文档撰写       |

## 七、许可证

本项目采用 MIT 许可证。详情请见 [LICENSE](LICENSE) 文件。

## 八、致谢

- 感谢南京大学 EL 程序设计大赛组委会提供的平台。
- 感谢 [Godot Engine](https://godotengine.org/) 提供的强大开源引擎。
- 感谢 [Ollama](https://ollama.com/) 提供的本地 AI 部署方案。

---
**如果觉得项目不错，请给我们一个 Star ⭐！**  
**如有任何问题或建议，欢迎提交 Issue 或 Pull Request。**
