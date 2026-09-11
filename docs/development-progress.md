# 开发进度

更新时间：2026-09-11

## 已完成

- 保留原始信号、伪影标记、PSD、specparam、频带功率、导出和单次 GUI 分析链路。
- 新增 `Project -> Subject -> Session -> Channel` 结构；Session 原始数组按独立 MAT 文件保存。
- 新增 `AnalysisRun` 元数据、数据版本和仅计算参数指纹；同配置第二次分析复用有效结果。
- 新增 `lfp_compare_project`，支持显式 Session 选择、visit_label 保留、通道级长表和配置不兼容提示。
- 新增旧 MAT 数据迁移预览/显式迁移入口及 GUI-free 批处理入口。
- 新增同一 Session 多文件同步 segment 追加接口，严格校验采样率、长度、时间轴和重复通道。
- 新增 CSV 到显式 Session 的导入桥接函数，支持 SceneRay 与已确认的通用 CSV 设置。
- 新增比较长表 CSV/MAT 导出函数，保留每行来源 run_id 和配置指纹。
- LFP 项目平台测试：3 项通过。

## 尚未完成

- GUI 尚未加入完整的 Subject–Session 树和比较工作区；现有单次分析 GUI 保持不变。
- 多文件合并为同一 Session 的同步校验和多段 segment 管理仍需继续实现。
- Comparison 的通道映射界面、统一参数重新分析按钮和趋势图仍需接入 GUI。

## 下一步

1. 将 Project 索引加载/保存桥接到 GUI 的数据管理区。
2. 增加多文件 Session 导入预览、重复文件检测和缺失源文件重新定位。
3. 在 GUI 中接入比较查询和点图，保持核心函数无界面依赖。

## 验证命令

```matlab
addpath('src');
results = runtests('tests/test_lfp_project_platform.m');
assert(all([results.Passed]));
```

完整测试仍使用：

```matlab
addpath('src');
results = runtests('tests');
assert(all([results.Passed]));
```
