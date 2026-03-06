[![Support on Afdian](https://img.shields.io/badge/Support-爱发电-orange.svg?style=flat-square&logo=afdian)](https://afdian.com/a/Rabbit-Spec)
<h1 align="center">iStoreOS-Flow</h1>

<p align="center">
  专为 iStoreOS (OpenWrt) 打造的 HomeAssistant 全能极简监控面板
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main/img/1.PNG?v=2" width="600"></img>
</p>

## ✨ 核心亮点

* **原生高效采集**：彻底抛弃老旧低效的文本截取，采用 OpenWrt 原生 `ubus` 总线与 `jsonfilter`，毫秒级响应，几乎零 CPU 负载。
* **一键全自动部署**：内置智能安装脚本，全自动搞定 SSH 免密认证握手、目录创建、脚本拉取与 YAML 配置注入，小白也能轻松上手。
* **全场景状态监控**：不仅涵盖 CPU、温度、内存、实时速率，更独创**“多物理硬盘自动轮播”**与**“物理网口拔插状态/协商速率”**可视化。
* **代理环境感知**：自动侦测 OpenClash, PassWall, PassWall2, Nikki 等主流科学上网插件的运行状态。
* **视觉巅峰体验**：深度定制的 Mushroom 模块化网格布局，配合 Card-mod 实现完美的圆角与阴影层级，专为跨设备（手机/平板/PC）响应式排版优化。

## 📂 仓库结构

```text
├── install.sh               # 🚀 一键全自动部署脚本 (核心)
├── packages/
│   └── istoreos_flow.yaml   # HA 核心配置文件 (含传感器拆解与现代模板换算)
├── shell/
│   └── istoreos_flow.sh     # 运行在 HA 容器内的数据采集核心脚本 (Bash)
├── dashboards/
│   └── dashboard.yaml       # 基于 Mushroom 的高颜值仪表盘卡片代码
├── themes/
│     └── mushroom-glass.yaml   # 适配明暗模式的毛玻璃主题文件
└── img/
    └── istoreos_flow-2.jpg  # 仪表盘顶图海报素材
```

## 🧩 依赖插件 (HACS)

在导入本项目配置前，请确保已在 **HACS 商店** 安装以下前端组件：
1. **Mushroom**：基础 UI 架构。
2. **Mini-Graph-Card**：用于显示趋势曲线。
3. **Card-mod**：核心视觉依赖，用于实现模糊效果。

## 🚀 快速开始 (一键部署)

### 1. 在 Home Assistant 的终端 (Terminal / SSH) 中直接粘贴并运行以下命令：

```bash
# 使用脚本一键安装
curl -sSL https://raw.githubusercontent.com/Rabbit-Spec/iStoreOS_Flow/main/spec/install.sh?$(date +%s) | bash
```

### 2. 应用主题 (Themes)
在 HomeAssistant 用户界面中应用 Mushroom Glass 主题

### 3. 导入仪表盘 (Dashboards)
新建仪表盘面板，将 `dashboards/dashboard.yaml` 内容粘贴至代码编辑器。


---

## ⚠️ 免责声明
* 请确保你的iStoreOS设备已开启 SSH 权限。
* 本脚本涉及模拟登录操作，请勿在公网环境下暴露 SSH 端口。

---

## ☕ 赞助与支持

如果你觉得 **Rabbit-Spec** 的「Surge自用配置以及模块和脚本」项目对你有帮助，欢迎请我喝杯咖啡。

👉 [点击前往爱发电支持我](https://afdian.com/a/Rabbit-Spec)

---

## 我用的机场
**我用着好用不代表你用着也好用，如果想要入手的话，建议先买一个月体验一下。任何机场都有跑路的可能。**<br>
> **「Nexitally」:** [佩奇家主站，一家全线中转线路的高端机场，延迟低速度快。](https://naiixi.com/signupbyemail.aspx?MemberCode=0b532ff85dda43e595fb1ae17843ae6d20211110231626) <br>

> **「TAG」:** [目前共有90+个国家地区节点，覆盖范围目前是机场里最广的。](https://482469.dedicated-afflink.com) <br>

---
