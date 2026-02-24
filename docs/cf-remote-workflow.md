# Cloudflare 远端优先工作流

## 目标

固定协作默认值：

1. 默认讨论对象始终是 Cloudflare 上的 Worker 页面、远端 D1、远端 R2。
2. 本地开发仅用于加速调试，不作为最终验收结果。
3. 每次功能完成后，必须部署到 Cloudflare Worker，再由网页实测验收。

## 默认规则

1. 任何涉及数据判断的查询，优先使用 `--remote`。
2. 如果同时查询本地和远端，必须明确标注来源，避免混淆。
3. 向用户汇报结果时，默认引用远端环境结果。

## 标准执行流程

1. 身份确认
```bash
npm run verify:auth
```

2. 本地开发（可选）
```bash
npm run dev:local
```
或连接远端绑定调试：
```bash
npm run dev:remote
```

3. 完成功能后部署到 Cloudflare
```bash
npm run deploy:cf
```

4. 部署后验证远端 D1
```bash
npm run verify:remote:d1
```

5. 让用户在 Cloudflare 页面实测

## 一键发布与验证

```bash
npm run release:cf
```

该命令会串行执行：

1. `verify:auth`
2. `deploy:cf`
3. `verify:remote:d1`

## 常见误区

1. 只看 `.wrangler/state` 的本地 SQLite 就下结论。
2. 本地验证通过但未部署远端就通知用户测试。
3. 查询 D1 时漏写 `--remote`，导致与线上页面数据不一致。

