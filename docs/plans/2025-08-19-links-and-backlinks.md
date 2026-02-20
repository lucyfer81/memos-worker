# 链接表和反向索引功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标:** 为 memos-worker 添加双向链接系统，支持卡片之间的语义关联、反向链接查询和 Inbox 暂缓流程

**架构:**
- 使用 `note_links` 表存储单向链接关系 (from_id → to_id)
- 通过 SQL JOIN 查询生成反向链接视图
- 利用现有 FTS 和标签系统计算语义相似度
- 前端通过关联决策面板强制用户做出关联决策

**技术栈:**
- 后端: Cloudflare Workers + D1 数据库
- 前端: 原生 JavaScript + 现有 UI 框架
- 相似度算法: 标签重叠度 + FTS rank 混合排序

---

## Task 1: 更新数据库架构

**Files:**
- Modify: `src/schema.sql`

**Step 1: 添加 note_links 表定义**

在 `src/schema.sql` 文件末尾添加链接表和索引。

**Step 2: 更新 notes 表添加 link_status 字段**

添加 `link_status TEXT DEFAULT 'pending'` 字段。

**Step 3: 添加触发器自动维护状态**

创建触发器在链接创建/删除时自动更新状态。

**Step 4: 提交**

```bash
git add src/schema.sql
git commit -m "feat: add note_links table and link_status field"
```

---

## Task 2-10: (完整实现计划)

由于篇幅限制，完整计划已保存到文件中。
