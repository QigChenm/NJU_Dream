<div align="center">
  <h1>最南幻想</h1>
  <p><strong>AI 情感陪伴 Galgame · 南京大学校园主题</strong></p>
  <p>
	<a href="https://github.com/QigChenm/GuTeamGame/releases"><img src="https://img.shields.io/badge/下载-Windows-blue?logo=windows" alt="Windows"></a>
	<a href="https://github.com/QigChenm/GuTeamGame/blob/main/docs/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
    <a href="https://qigchenm.github.io/NJU_Dream/"><img src="https://img.shields.io/badge/项目网站-最南幻想-ff69b4?logo=google-chrome" alt="Website"></a>
  </p>
</div>




## 一、项目简介

**最南幻想** 是一款基于 Godot 4 引擎开发的 AI 驱动 Galgame，专为大学生群体设计。游戏以南大鼓楼校区为背景，通过大语言模型实时生成对话与剧情，提供个性化、沉浸式的情感陪伴体验。玩家可以与 AI 角色进行多轮对话、触发分支剧情、解锁精美 CG 和音乐，在春去冬来的季节流转中感受温暖与感动。

## 二、核心特色

### 🤖 全 AI 实时叙事，每一次选择都改变故事

![choose](./index/choose.png)

告别千篇一律的文本，**游戏中的所有剧情、对话乃至角色情绪，均由先进的大语言模型实时生成**。你不再是被动阅读，而是故事的共同创作者。每一次对话，每一个选择，都会即时影响角色的反应、好感度以及后续剧情的走向。AI 能理解上下文，记住你之前说过的话，给出连贯、富有情感的回答，创造出完全属于你自己的独特校园记忆。

### 💡 智能双模式：本地极速与云端高智，自由切换

![settings](./index/settings.png)

为了满足不同场景的需求，我们独创了双重 AI 模式：

- **本地模式**：基于 Ollama，支持一键部署千问、Llama、DeepSeek 等多款主流模型。无需网络，延迟极低，完全免费，数据隐私安全。特别优化了 JSON 解析，智能修复 AI 输出格式，确保剧本稳定运行。
- **云端模式**：无缝接入 Kimi、DeepSeek 等云端大模型 API，享受最顶级的智能与创造力。只需填入 API Key，即可解锁更丰富的剧情生成能力。
  无论你是在校园网下，还是在离线环境，都能找到最适合的 AI 伴侣。

### 🎨 沉浸式视听演出，打造电影级 Galgame 体验

![performance](./index/auto1.png)

我们不止于文字。游戏内建了一套强大的演出引擎：

- **角色系统**：每个角色拥有丰富的表情（喜怒哀乐）和动作（弹跳、抖动、点头等），并配有呼吸、眨眼等动态细节，栩栩如生。
- **场景系统**：支持淡入淡出、滑动等转场特效，以及樱花、飘雪、萤火虫、落叶等动态粒子效果，配合动态 CG 与全屏长对话，营造出浪漫或静谧的校园氛围。
- **音频系统**：多声道 BGM、音效与语音控制，音乐可随剧情淡入淡出，完美烘托情绪。
- **背景展示窗**：无需解锁即可在“鉴赏”界面浏览游戏中所有精美的校园场景原画，感受南大四季之美。

### 📚 完备的商业级 Galgame 功能体系

我们为你准备了所有你期待的视觉小说经典功能，并进行了现代化的升级：

![save](./index/save.png)

**存读档系统**：支持多达 54 个存档槽位，带缩略图和章节信息，可翻页、删除、重排。更提供**快速存档/读档**，一键保存或回到最新进度。

![logs](./index/logs.png)

**对话历史**：随时回看之前的对话，支持文本的分段展示，长对话和玩家选择均被清晰记录。

![gallery](./index/gallery.png)

**好感度与鉴赏**：通过选择提升角色好感度，解锁专属剧情。在“鉴赏”模式中，可以随时查看已解锁的 CG 原画、背景音乐和场景原画。

![auto](./index/auto.png)

**自动/快进模式**：解放双手，自动模式下文本显示完毕自动前进；快进模式则能快速跳过已读内容，让你专注于关键选择。

**个性化设置**：自由调节文本显示速度、自动播放延迟、BGM/音效/语音音量、全屏切换，甚至一键切换 AI 服务商和模型。

### ❤️ 深耕校园心理关怀，用故事疗愈心灵

![care](./index/dialogue.png)

游戏以南大鼓楼、仙林、苏州校区为舞台，所有场景均为实地取景或基于真实建筑绘制。剧情设计上，我们特别融入了**“大学生心理减压”** 的主线：在北大楼下感受百年的沉静、在大礼堂聆听音乐疗愈、在心理咨询中心体验正念冥想、在操场用汗水释放压力。通过 AI 角色“小貅”与“宋青学长”的陪伴与引导，我们希望这款游戏能成为南大学子乃至所有大学生的心灵树洞，**让每一次对话都成为一次温暖的自我发现。**

## 三、快速开始

### 1. 下载与运行

- 前往 [Releases 页面](https://github.com/QigChenm/GuTeamGame/releases) 下载对应平台的最新版本压缩包。
- 解压后直接运行 `最南幻想.exe` (Windows) 或 `最南幻想.app` (macOS)。

### 2. 配置 AI 服务（重要！）

**开始游戏前，请先进入游戏主菜单的「游戏设置 → AI设置」页面，选择你的 AI 连接方式。** 游戏默认使用本地 Ollama，如果你希望直接体验，请确保已安装并启动 Ollama。

#### 🌐 选项一：一键部署本地 AI

游戏目录下提供了 `deploy_ollama.bat` 脚本，可以自动帮你安装 Ollama 并下载推荐模型（千问 7B）。
你也可以在游戏内的**「游戏设置」**界面点击 **「Ollama一键部署」** 按钮来启动该脚本。
部署完成后，在设置页选择 `Ollama 本地`，模型选择 `qwen2.5:7b-instruct` 即可。

#### 🖥️ 选项二：手动配置本地 Ollama

1. 安装 [Ollama](https://ollama.com/)。
2. 打开终端，下载模型：`ollama pull qwen2.5:7b-instruct`。
3. 启动 Ollama 服务：`ollama serve`。
4. 在游戏设置中选择 `Ollama 本地`，模型为 `qwen2.5:7b-instruct`。

#### ☁️ 选项三：使用云端 API（推荐）

1. 在「设置 → AI设置」中选择服务商和模型。
2. 填写该服务商对应的 **API Key**。普通玩家无需填写 Base URL。
3. 游戏会自动保存这些设置，后续可直接使用。

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

表格中排名不分先后：

| 成员   | 职责                                     |
| :----- | :--------------------------------------- |
| 赵卿成 | 项目负责人、核心框架开发、游戏系统设计   |
| 俞天镒 | AI 开发与集成、提示词工程、本地模型部署  |
| 汤艺暄 | 美术设计（角色立绘、背景、UI、游戏网站） |
| 卞涵砚 | PPT制作、剧情测试、文档撰写、网站开发    |

## 七、许可证

本项目采用 MIT 许可证。详情见 [LICENSE](https://github.com/QigChenm/GuTeamGame/blob/main/docs/LICENSE)。

## 八、致谢

- 南京大学 EL 程序设计大赛组委会
- [Godot Engine](https://godotengine.org/)
- [Ollama](https://ollama.com/)

**喜欢的话请给我们一个 Star ⭐！**
