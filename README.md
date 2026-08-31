<div align="center">
  <img src="products/phone/src/main/resources/base/media/appIcon.png" width="112" alt="格异录应用图标">
  <h1>格异录 · Anomicon</h1>
  <p>一款为 HarmonyOS 打造的非官方 SCP 中文阅读与探索应用。</p>
</div>

> [!IMPORTANT]
> 格异录是非官方社区项目，与 SCP Wiki 不存在隶属、合作或认可关系。应用展示的 SCP 内容及相关素材归各自创作者所有。

## 功能

- **探索**：浏览高评分、近期翻译、原创与搞笑条目，也可以从每日推荐开始阅读。
- **图鉴与故事**：按系列查看 SCP 档案和故事，支持搜索与筛选。
- **原生阅读**：将 Wiki 页面整理为 ArkUI 原生内容，支持图片预览、字号与行距调整，并自动恢复阅读位置。
- **个人资料库**：保存收藏、阅读历史和进度，根据本地阅读活动生成研究档案。
- **离线与弱网体验**：缓存目录、文章和图片；网络不稳定时，优先展示设备上已有的内容。
- **三维档案**：使用 ArkGraphics3D 展示经过整理的 GLB 模型。经典项目可随应用提供，其余档案支持按需下载和删除。
- **HarmonyOS 原生界面**：采用 ArkUI、HDS 导航和系统材质，适配深浅色主题、沉浸式页面与触感反馈。

## 下载与安装

请从项目发布页下载最新的 `.hap` 安装包。当前版本面向 HarmonyOS 6.0（API 26）设备，具体兼容范围和已知问题以对应版本的发布说明为准。

安装来自应用市场以外的安装包时，系统可能要求确认安装来源。请只从本项目发布页获取文件，并在安装前核对发布说明中提供的版本与文件校验值。

## 技术实现

- HarmonyOS SDK 6.0.0（API 26）
- ArkTS / ArkUI
- HDS（`@kit.UIDesignKit`）
- ArkData RDB 与 Preferences
- ArkWeb、Remote Communication Kit、ArkGraphics3D
- Hvigor / OHPM

项目采用 `products → features → common` 的多模块结构，并在各功能模块内划分领域、应用、数据、界面与装配层。

```text
Anomicon/
├── AppScope/                    # 应用级配置与图标
├── common/anomiconbasic/        # 基础组件、平台端口、缓存与通用 UI
├── features/
│   ├── article/                 # 文章获取、解析、缓存与原生渲染
│   ├── archive3d/               # 三维资源清单、下载、校验与领域逻辑
│   ├── catalog/                 # SCP 图鉴、故事目录、搜索与预览
│   ├── explore/                 # 推荐与内容发现
│   ├── library/                 # 收藏、历史、阅读进度与研究活动
│   ├── settings/                # 主题、阅读与应用设置
│   └── terminal/                # 个人资料库与研究档案
├── products/phone/              # 手机端应用、路由与依赖装配
└── tools/archive3d/             # 三维资源检查与预处理工具
```

## 数据与权限

应用从 [SCP 基金会中文 Wiki](https://scp-wiki-cn.wikidot.com/) 获取公开页面，并在设备上保存目录、文章和图片缓存，以及收藏和阅读记录。部分三维模型随应用提供，其余模型从资源清单记录的固定上游版本按需下载，并在使用前校验文件大小和 SHA-256。

应用使用以下权限：

- `ohos.permission.INTERNET`：加载 Wiki 内容、图片和按需三维资源。
- `ohos.permission.VIBRATE`：提供可在设置中关闭的触感反馈。

## 许可与署名

仓库中的应用源代码使用 [Apache License 2.0](LICENSE) 许可。

SCP 相关文字、概念和部分视觉资源不适用 Apache License 2.0，它们依据各自的上游声明及 [Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/) 使用。三维模型的来源、作者、固定版本和修改说明见 [`scp-model-attribution.txt`](products/phone/src/main/resources/rawfile/licenses/scp-model-attribution.txt)。分发衍生版本前，请保留完整署名并复核 [SCP 许可指南](https://scp-foundation.net/licensing-guide)。
