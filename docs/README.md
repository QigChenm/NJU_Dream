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

- 前往 [Releases 页面](https://github.com/QigChenm/GuTeamGame/releases) 下载对应平台的最新版本压缩包。
- 解压后直接运行 `最南幻想.exe` (Windows) 或 `最南幻想.app` (macOS)。

### 2. 配置 AI 服务（重要！）

**开始游戏前，请先进入游戏主菜单的「游戏设置 → AI设置」页面，选择你的 AI 连接方式。** 游戏默认使用本地 Ollama，如果你希望直接体验，请确保已安装并启动 Ollama。

#### 🌐 选项一：一键部署本地 AI（推荐）

游戏目录下提供了 `deploy_ollama.bat` 脚本，可以自动帮你安装 Ollama 并下载推荐模型（千问 7B）。
你也可以在游戏内的**「游戏设置」**界面点击 **「Ollama一键部署」** 按钮来启动该脚本。
部署完成后，将 AI 地址设置为 `http://localhost:11434/v1`，模型选择 `qwen2.5:7b-instruct` 即可。

#### 🖥️ 选项二：手动配置本地 Ollama

1. 安装 [Ollama](https://ollama.com/)。
2. 打开终端，下载模型：`ollama pull qwen2.5:7b-instruct`。
3. 启动 Ollama 服务：`ollama serve`。
4. 在游戏设置中确认 AI 地址为 `http://localhost:11434/v1`，模型为 `qwen2.5:7b-instruct`。

#### ☁️ 选项三：使用云端 API

1. 在「设置 → AI设置」中填写你的 **Base URL**（例如 `https://api.deepseek.com/v1`）、**Model**（例如 `deepseek-chat`）和 **API 密钥**。
2. 游戏会自动保存这些设置，后续可直接使用。

### 3. 操作说明

- **鼠标点击 / 空格键**：推进对话
- **鼠标左键**：选择选项
- **鼠标右键**：打开好感度面板
- **A 键**：切换好感度面板
- **HUD 按钮**：存档、读档、设置、自动模式等

## 四、项目结构

```text
res://
├── scenes/                 # 场景文件
├── scripts/                # 核心脚本
│   ├── datatypes/          # 自定义资源类型
│   ├── managers/           # 自动加载管理器
│   ├── plugins/            # 辅助插件
│   └── scenes/             # 场景脚本
├── assets/                 # 资源（图片、音频、字体）
├── config/                 # 配置文件
├── docs/                   # 文档（README、操作手册）
└── project.godot
```

## 五、技术栈

- **游戏引擎**：Godot 4.6.2 (GDScript)
- **AI 接口**：Ollama / 云端 API (HTTP)
- **指令体系**：自定义 JSON DSL 命令流
- **数据存储**：本地 JSON 存档 + ConfigFile
- **音频系统**：AudioServer 多总线管理

## 六、贡献者

| 成员   | 职责                                       |
| :----- | :----------------------------------------- |
| 赵卿成 | 项目负责人、核心框架开发、游戏系统设计     |
| 俞天镒 | AI 模块、提示词工程、本地模型部署          |
| 汤艺暄 | 美术设计（角色立绘、背景、UI、游戏网站）   |
| 卞涵砚 | 音频资源制作、剧情测试、文档撰写、网站开发 |

## 七、许可证

本项目采用 MIT 许可证。详情见 [LICENSE](https://license/)。

## 八、致谢

- 南京大学 EL 程序设计大赛组委会
- [Godot Engine](https://godotengine.org/)
- [Ollama](https://ollama.com/)

**喜欢的话请给我们一个 Star ⭐！**
