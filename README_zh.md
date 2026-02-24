[English](./README.md)

# Memos Worker: 由 Cloudflare 驱动的笔记与知识库

![1](./image/1.png)
![1](./image/2.png)
![1](./image/3.png)
![1](./image/4.png)

**Memos Worker** 是一个功能强大、性能卓越的无服务器笔记和知识库应用。它完全构建在 Cloudflare 的生态系统之上（Workers, Pages, D1, R2, KV），为你提供一个可以永久拥有、近乎零成本的私有化笔记解决方案。

## ✨ 功能特点

-   **✍️ Markdown 全功能支持**: 支持实时预览、分栏编辑，并能从富文本智能粘贴为 Markdown。
-   **🎛️ 灵活视图与工作流**: 支持笔记的归档、收藏与置顶。提供宽屏、瀑布流、日期分组等多种视图模式。
-   **📚 强大组织能力**: 自动标签、全文搜索、时间线、日历和活动热力图。
-   **🗂️ 文件与附件**: 支持拖拽或粘贴上传图片（可存至 R2 或 Imgur）及各类文件附件。
-   **🔗 公开分享**: 可以为笔记中的任意 Memos 或文件生成唯一的公开访问链接，并支持设置过期时间。
-   **🤖 Telegram 集成**: 通过 Telegram Bot 随时随地记录文本、图片、视频和文件。
-   **🎨 高度可定制**: 支持浅色/深色主题、自定义主色调、背景图片、玻璃模糊效果，以及对布局和功能可见性的精细调整。
-   **📃 知识库 (Docs)**: 独立的树状文档中心，适合构建结构化的知识体系。
-   **🚀 极致性能与低成本**: 基于 Cloudflare 全球网络，响应迅速，在免费套餐额度内几乎零成本运行。

## 🚀 部署指南

### 第 1 步: 选择你的仓库创建方式

你有两种方式来创建你自己的代码仓库，请根据你的需求选择其一。

#### 选项 A: Fork (推荐，便于更新)
-   **优点**: 你的仓库会与我们的原始仓库保持关联。当项目有新功能或修复时，你可以轻松地从 GitHub 同步这些更新。
-   **缺点**: 你的代码仓库是**公开**的。（由于关键信息通过环境变量配置，唯一暴露的是cloudflare的数据库、KV、R2的id，但通常也不会有什么事）
-   **操作**: 点击本页面右上角的 **"Fork"** 按钮。

#### 选项 B: 使用模板 (仓库可设为私有)
-   **优点**: 你可以创建一个全新的、独立的、并且**私有**的代码仓库。
-   **缺点**: 你的仓库将与原始项目完全独立，**无法自动或轻松地获取未来的更新**。你需要手动通过 Git 命令来同步，过程较为复杂。
-   **操作**: 点击本页面右上角的 **"Use this template"** -> **"Create a new repository"**。

### 第 2 步: 创建 Cloudflare 资源

你需要在 Cloudflare Dashboard 中手动创建好项目所需的 D1 数据库、R2 存储桶和 KV 命名空间。

| 资源类型 | 推荐名称 | 绑定变量名 |
| --------------- | ----------------- | ----------------- |
| **D1 数据库** | `notes-db` | `DB` |
| **KV 命名空间** | `notes-kv` | `NOTES_KV` |
| **R2 存储桶** | `notes-r2-bucket` | `NOTES_R2_BUCKET` |

1.  **创建 D1 数据库 (`notes-db`)**:
	-   进入 **Workers & Pages** -> **D1** -> **Create database**。
	-   **重要**: 创建后，进入数据库控制台，将项目目录下的 `schema.sql` 文件内容完整复制进去并执行。
    -   **重要**: 记下database_id和database_name，写入 `wrangler.toml` 文件的 `[[d1_databases]]` 部分。

2.  **创建 KV 命名空间 (`notes-kv`)**:
	-   进入 **Workers & Pages** -> **KV** -> **Create a namespace**。
	-   **重要**: 记下 `id`。将其填入 `wrangler.toml` 文件的 `[[kv_namespaces]]` 部分。

3.  **创建 R2 存储桶 (`notes-r2-bucket`)**:
	-   进入 **R2** -> **Create bucket**。
	-   **重要**: 记下 `bucket_name`。将其填入 `wrangler.toml` 文件的 `[[r2_buckets]]` 部分。

### 第 3 步: 部署到 Cloudflare Workers

1.  进入 Cloudflare Dashboard -> **Workers & Pages** -> **Create application** -> **选择Workers** -> **连接刚才创建的Git库**。
2.  选择你 Fork 的仓库，然后直接点击 **Save and Deploy**。

### 第 4 步: 配置环境变量

部署完成后，进入你创建的 Worker 项目进行配置。

1.  进入项目 -> **Settings**，进入 **Environment Variables**，添加以下变量：

	| Variable Name           | Description                          |
    | ----------------------- | ------------------------------------ |
	| `USERNAME`              | 你的登录用户名                       |
	| `PASSWORD`              | 你的登录密码                         |
	| `TELEGRAM_BOT_TOKEN`    | (可选) Telegram 机器人的 Token       |
	| `TELEGRAM_WEBHOOK_SECRET` | (可选) 一个随机长字符串用于 Webhook 验证 |
	| `AUTHORIZED_TELEGRAM_IDS` | (可选) 授权使用机器人的 Telegram 用户 ID |

2.  重新部署，让所有配置生效。

### 第 5 步: (可选) 激活 Telegram Webhook

如果你配置了 Telegram 相关的变量，你需要一次性地激活 Webhook。

1.  获取你的应用 URL (例如 `https://your-project.pages.dev`)。
2.  在你的浏览器地址栏中，构造如下的 Webhook 激活链接：
	```
	https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://your-project.pages.dev/api/telegram_webhook/<TELEGRAM_WEBHOOK_SECRET>&secret_token=<TELEGRAM_WEBHOOK_SECRET>
	```
3.  **替换**链接中的 `<TELEGRAM_BOT_TOKEN>` 和 `<TELEGRAM_WEBHOOK_SECRET>` 为你自己的真实密钥值。
4.  按下回车。如果你看到 `{"ok":true,"result":true,"description":"Webhook was set"}` 的返回信息，即代表设置成功！你现在可以给你的机器人发送消息了。

---

> 此外还可以直接使用wrangler，通过命令行部署（我使用的版本是^4.33.0）
>
> 1. 克隆仓库到本地，把KV D1 R2的配置填入到wrangler.toml里面
> 2. 执行`npx wrangler deploy`

## 💡 使用技巧

-   **预览原始文件内容**: 在主界面或公开分享页面，你可以**右键点击**任何基于文本的附件（如 `.txt`, `.md`, `.json`, `.js`），在新标签页中直接打开并预览其原始内容。
-   **理解 'Telegram Proxy' 的作用**: 这个在设置面板中的选项，用于控制如何处理从 Telegram 发送的视频和文件。
    -   **代理开启**: 节省 R2 存储空间。你的应用会创建一个指向 Telegram 文件的“代理”链接。**风险**: 如果原始文件从 Telegram 被删除，你的链接将会失效。
    -   **代理关闭**: 使用 R2 存储。你的应用会从 Telegram 下载文件并重新上传到你自己的 R2 桶中，以确保你拥有一个永久的副本。
-   **理解 (Keep Time) 的作用**: 在编辑笔记时，你会看到一个 "Keep Time" 的复选框。
    -   **勾选 (默认)**: 保存编辑后，笔记的原始时间戳将被保留，它**不会**跑到时间线的顶端。
    -   **不勾选**: 保存后，笔记的时间戳会更新为当前时间，使其成为最新的笔记。

## 🔍 重建搜索索引 (推荐)

如果你是从旧版本（20260206之前版本）更新的，并且想要实现**搜索文件名**的功能，你需要重建全文搜索 (FTS) 索引。

1.  进入 Cloudflare Dashboard -> **Workers & Pages** -> **D1**。
2.  选择你的数据库 (例如 `notes-db`)。
3.  点击 **Console** 选项卡。
4.  复制本项目中 `src/migrate_fts.sql` 文件的完整内容并粘贴到控制台。
5.  点击 **Execute**。

这将更新你的搜索索引以包含文件名，并刷新所有现有数据。

## 🔧 项目开发 (Wrangler)

### 1. 本地开发 (模拟环境)

**初始化本地数据库**:
```bash
npx wrangler d1 execute YOUR_D1_NAME --local --file=./src/schema.sql
```

**启动开发服务器**:
```bash
npx wrangler dev
```

### 2. 本地开发 (连接云端真实资源)

此模式将你的本地开发服务器连接到你在 Cloudflare 上创建的真实资源。

1.  **配置 `wrangler.toml`**: 确保你在 Cloudflare Dashboard 中创建的资源 ID 已经填入此文件。
	```toml
	# wrangler.toml
	[[d1_databases]]
	binding = "DB"
	database_name = "notes-db"
	database_id = "YOUR_D1_DATABASE_ID" # 替换

	[[kv_namespaces]]
	binding = "NOTES_KV"
	id = "YOUR_KV_NAMESPACE_ID" # 替换

	[[r2_buckets]]
	binding = "NOTES_R2_BUCKET"
	bucket_name = "notes-r2-bucket"
	```
2.  **创建 `.dev.vars` 文件**: 在项目根目录创建此文件，用于存放你的本地密钥。
	```ini
	# .dev.vars (此文件会被 Git 忽略)
	USERNAME="dev_user"
	PASSWORD="dev_password"
	```
3.  **启动连接到云端的开发服务器**:
	```bash
	npx wrangler dev --remote
	```

## ✅ 远端优先协作流程（默认）

从现在起，默认以 Cloudflare 线上环境作为“真实结果”来源：

1. 默认讨论的是 Cloudflare 页面、远端 D1、远端 R2。
2. 本地开发服务器仅用于调试，不作为最终验收结果。
3. 每次改动完成后，必须部署到 Cloudflare Worker 后再测试。

推荐命令：

```bash
# 检查 wrangler 登录状态
npm run verify:auth

# 本地调试（可选）
npm run dev:local

# 连接远端绑定调试（可选）
npm run dev:remote

# 部署到 Cloudflare
npm run deploy:cf

# 校验远端 D1（明确使用 --remote）
npm run verify:remote:d1

# 一键：认证检查 + 部署 + 远端校验
npm run release:cf
```

详细流程见：[`docs/cf-remote-workflow.md`](docs/cf-remote-workflow.md)
