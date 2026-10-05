# 未名溪谷应用源码

使用、构建、升级与恢复方式见 [项目说明](../README.md)。

- domain.dart / research.dart：账户计算、schema7 备份、资料与引用模型。
- services.dart：东方财富日线与 DeepSeek HTTPS 客户端。
- credentials.dart：与研究备份分开的系统安全存储。
- storage.dart：v1/v2/v3/v4/v6 迁移、持久化及原文件保护。
- broker_import.dart / broker_sync.dart / broker_widgets.dart：完整持仓文件解析、人工预览与 Windows 前台读取；不含券商登录或直连。
- main.dart / forms.dart / research_widgets.dart：双端响应式界面。

- portfolio_history.dart / portfolio_history_widgets.dart：单账户导入事件、容量保护、完整差异与恢复。
- risk_charts.dart：复用账户计算的风险图表、全量明细和压力交互。
- quant_models.dart / quant_engine.dart / quant_widgets.dart：可配置规则版本、可追溯因子计算、筛选评分及贡献/对照图。
- data_foundation.dart / data_foundation_widgets.dart：未复权历史日线与带日期资金流水、预览确认和期初累计保留。
