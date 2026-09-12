# 开发进度

更新时间：2026-09-12

## 已完成

- 保留原始信号、伪影标记、PSD、specparam、频带功率、导出和单次 GUI 分析链路。
- 新增 `Project -> Subject -> Session -> Channel` 结构；Session 原始数组按独立 MAT 文件保存。
- 新增 `AnalysisRun` 元数据、数据版本和仅计算参数指纹；同配置第二次分析复用有效结果。
- 新增 `lfp_compare_project`，支持显式 Session 选择、visit_label 保留、通道级长表和配置不兼容提示。
- 新增旧 MAT 数据迁移预览/显式迁移入口及 GUI-free 批处理入口。
- 新增同一 Session 多文件同步 segment 追加接口，严格校验采样率、长度、时间轴和重复通道。
- 新增 CSV 到显式 Session 的导入桥接函数，支持 SceneRay 与已确认的通用 CSV 设置。
- 新增比较长表 CSV/MAT 导出函数，保留每行来源 run_id 和配置指纹。
- 新增 `launchLfpProjectApp` / `LfpProjectApp` 原生项目工作区，提供数据管理、单次分析和结果比较三个基础 Tab。
- LFP 项目平台与审查回归测试已通过（当前开发机完整套件 89/89；其中审查回归 8/8）。

## 尚未完成

- 项目工作区已提供条件筛选、稳定通道映射和显式统一参数重算入口；普通比较不会从当前查看 Session 静默补算其他记录。
- 多文件导入使用独立通道缓存和多段 data_ref；不同长度、采样率或时间轴的通道不会被强行拼接。
- 比较结果按数据版本、通道快照、配置和模块产物校验；stale run 仅保留作历史记录。
- 项目写操作共用原子目录锁和 staging 诊断标记；结果写入也受锁保护，保存索引带单调 project revision，批处理可启用严格冲突检查。
- PSD 会记录 requested/effective 频率范围、每通道有效窗口和 DPSS provider；默认频带边界不会因 FFT 网格舍入而被误判为越界。

## 下一步

1. 继续扩展项目级故障注入和并发写入测试。
2. 用 MATLAB Profiler 对大规模通道预览和导入进行基准测量。
3. 在不改变核心结果语义的前提下完善后续 GUI 交互。

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

最近一次 R2024a 开发机回归结果：`passed=89, failed=0, incomplete=0`。运行时若 MATLAB 路径包含完整 FieldTrip `genpath`，可能出现兼容目录遮蔽和 SPM 多版本提示；项目会记录 DPSS provider 并在 shadowing 时使用受控 native 实现。
