#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成课程大作业（小作业1、2、3）配套高清专业图表
运行环境: Python 3 with matplotlib, numpy, pillow
"""

import os
from pathlib import Path
import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import FancyBboxPatch, Rectangle, Circle, Arrow
from PIL import Image

# 基础路径配置
OUTPUT_DIR = Path("/Users/chenweiyang/Documents/Project/课程大作业_工程伦理与项目管理/images")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 字体与排版设置
plt.rcParams['font.sans-serif'] = ['PingFang SC', 'Heiti SC', 'Songti SC', 'Arial Unicode MS', 'sans-serif']
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams['figure.dpi'] = 300
plt.rcParams['savefig.dpi'] = 300

# 专业科技配色方案 (Navy / Teal / Orange / Coral / Slate / Green)
NAVY = "#18324A"
TEAL = "#1F7A8C"
ORANGE = "#E27D60"
CORAL = "#E05A47"
SLATE = "#5C6B73"
LIGHT_BG = "#F4F7F9"
GREEN = "#2B9348"
CARD_BORDER = "#D0DBE5"
ACCENT_BLUE = "#2E86AB"

print("开始生成全套大作业高清图表...")

# ==============================================================================
# 图 1-1: 计算机健康工程系统多维度影响模型 (小作业1)
# ==============================================================================
def make_fig1_1():
    categories = ['健康促进与防范\n(Health)', '系统安全与可靠\n(Safety)', '绿色低碳与环境\n(Environment)', 
                  '法律合规与隐私\n(Legal)', '经济可持续与普惠\n(Economic & Social)']
    N = len(categories)
    
    # 评分数据
    values = [92, 95, 90, 96, 88]
    values += values[:1]  # 闭合曲线
    
    angles = [n / float(N) * 2 * np.pi for n in range(N)]
    angles += angles[:1]
    
    fig, ax = plt.subplots(figsize=(8, 7), subplot_kw=dict(polar=True))
    ax.set_facecolor("#FAFCFD")
    
    # 绘制雷达图网格
    ax.set_theta_offset(np.pi / 2)
    ax.set_theta_direction(-1)
    
    plt.xticks(angles[:-1], categories, size=11, color=NAVY, weight='bold')
    
    ax.set_rlabel_position(0)
    plt.yticks([40, 60, 80, 100], ["40分", "60分", "80分", "100分"], color=SLATE, size=9)
    plt.ylim(0, 100)
    
    # 绘制多边形与填充
    ax.plot(angles, values, linewidth=2.5, linestyle='solid', color=TEAL, marker='o', markersize=7)
    ax.fill(angles, values, color=TEAL, alpha=0.25)
    
    # 标注各个顶点的关键工程指标
    details = [
        "基线比对/消除疑病/低焦虑",
        "端侧沙盒/故障隔离/数据校验",
        "端侧智能/低功耗/节约90%算力",
        "PIPL敏感信息/GDPR/SaMD明界",
        "降低公共医保/适老化/零硬件门槛"
    ]
    for angle, value, text in zip(angles[:-1], values[:-1], details):
        ha = 'center'
        va = 'bottom' if angle in [0, np.pi] else ('left' if angle < np.pi else 'right')
        ax.annotate(f"{value}分\n[{text}]", xy=(angle, value), xytext=(angle, value + 8),
                    textcoords='polar', ha=ha, va='center', size=8.5, color=NAVY,
                    bbox=dict(boxstyle="round,pad=0.3", fc="#FFFFFF", ec=CARD_BORDER, lw=0.8, alpha=0.9))
        
    plt.title("图1-1 计算机健康工程系统（知衡）五维影响与可持续发展评估模型", size=13, weight='bold', color=NAVY, pad=25)
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig1_1_multi_dimension_impact.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 1-2: 个人健康数据隐私保护与合规分级架构图 (小作业1)
# ==============================================================================
def make_fig1_2():
    fig, ax = plt.subplots(figsize=(10, 5.8))
    ax.set_facecolor(LIGHT_BG)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 6)
    ax.axis('off')
    
    # 标题
    ax.text(5, 5.6, "图1-2 计算机健康工程“端侧沙盒-最小化脱敏-合规代理”分级安全架构", 
            ha='center', va='center', fontsize=13, weight='bold', color=NAVY)
    
    # 区域划分：本地安全边界 vs 网络边界
    # 1. 本地沙盒（左侧大框）
    box_local = FancyBboxPatch((0.4, 0.4), 6.0, 4.8, boxstyle="round,pad=0.15", 
                               fc="#EBF2F7", ec=ACCENT_BLUE, lw=1.5, ls='--')
    ax.add_patch(box_local)
    ax.text(3.4, 4.9, "【用户端侧完全可控域 (On-Device Protected Domain)】\n遵循《个人信息保护法》敏感个人信息单独同意原则", 
            ha='center', va='center', fontsize=9.5, weight='bold', color=ACCENT_BLUE)
    
    # 2. 外部网络（右侧大框）
    box_cloud = FancyBboxPatch((6.8, 0.4), 2.8, 4.8, boxstyle="round,pad=0.15", 
                               fc="#FDF5F2", ec=CORAL, lw=1.5, ls=':')
    ax.add_patch(box_cloud)
    ax.text(8.2, 4.9, "【隔离外部算力域】\n受限AI代理与加密推理", 
            ha='center', va='center', fontsize=9.5, weight='bold', color=CORAL)
    
    # 内部层级卡片
    # 卡片1: Apple HealthKit 数据源
    c1 = FancyBboxPatch((0.8, 3.2), 2.2, 1.2, boxstyle="round,pad=0.1", fc="white", ec=CARD_BORDER, lw=1)
    ax.add_patch(c1)
    ax.text(1.9, 3.9, "Apple HealthKit\n生理指标源", ha='center', va='center', fontsize=9.5, weight='bold', color=NAVY)
    ax.text(1.9, 3.45, "心率/HRV/步数/睡眠\n(只读授权，严禁外泄)", ha='center', va='center', fontsize=7.5, color=SLATE)
    
    # 卡片2: SwiftData 主观日记
    c2 = FancyBboxPatch((0.8, 1.0), 2.2, 1.2, boxstyle="round,pad=0.1", fc="white", ec=CARD_BORDER, lw=1)
    ax.add_patch(c2)
    ax.text(1.9, 1.7, "SwiftData 本地库\n主观感受与事件", ha='center', va='center', fontsize=9.5, weight='bold', color=NAVY)
    ax.text(1.9, 1.25, "精力/压力/生活事件\n(本地加密SQLite存储)", ha='center', va='center', fontsize=7.5, color=SLATE)
    
    # 卡片3: 本地算法引擎（守门员）
    c3 = FancyBboxPatch((3.6, 1.8), 2.4, 2.0, boxstyle="round,pad=0.1", fc="white", ec=TEAL, lw=1.8)
    ax.add_patch(c3)
    ax.text(4.8, 3.4, "知衡本地确定性引擎", ha='center', va='center', fontsize=10, weight='bold', color=TEAL)
    ax.text(4.8, 2.9, "• 数据质量守门 (门槛过滤)\n• 稳健基线分析 (28天MAD)\n• 事实包白名单构建\n• 阻断全部原始时间戳与采样", 
            ha='center', va='center', fontsize=7.8, color=NAVY)
    ax.text(4.8, 2.05, "【GDPR 隐私设计规范】", ha='center', va='center', fontsize=7.5, weight='bold', color=GREEN)
    
    # 卡片4: AI Proxy 与模型网关
    c4 = FancyBboxPatch((7.0, 1.8), 2.4, 2.0, boxstyle="round,pad=0.1", fc="white", ec=CORAL, lw=1.2)
    ax.add_patch(c4)
    ax.text(8.2, 3.4, "AI 安全合规网关", ha='center', va='center', fontsize=10, weight='bold', color=CORAL)
    ax.text(8.2, 2.85, "• HTTPS/TLS 加密传输\n• 临时会话零留存\n• 严禁用于基础模型训练\n• 客户端结构化强制校验", 
            ha='center', va='center', fontsize=7.8, color=NAVY)
    ax.text(8.2, 2.05, "【免责与非诊疗红线】", ha='center', va='center', fontsize=7.5, weight='bold', color=CORAL)
    
    # 连接箭头
    ax.annotate('', xy=(3.55, 3.6), xytext=(3.05, 3.6), arrowprops=dict(facecolor=ACCENT_BLUE, edgecolor='none', width=1.5, headwidth=6))
    ax.annotate('', xy=(3.55, 1.8), xytext=(3.05, 1.8), arrowprops=dict(facecolor=ACCENT_BLUE, edgecolor='none', width=1.5, headwidth=6))
    ax.annotate('', xy=(6.95, 2.8), xytext=(6.05, 2.8), arrowprops=dict(facecolor=TEAL, edgecolor='none', width=2.0, headwidth=7))
    ax.text(6.5, 3.1, "仅传最小化\n抽象事实包", ha='center', va='center', fontsize=7.5, weight='bold', color=TEAL)
    
    # 底部法律合规说明栏
    box_law = FancyBboxPatch((0.4, 0.05), 9.2, 0.45, boxstyle="square,pad=0", fc="#E2E8F0", ec='none')
    ax.add_patch(box_law)
    ax.text(5, 0.27, "合规法律依据：《中华人民共和国个人信息保护法》第28条（敏感个人信息）；《数据安全法》；原国家药监局医疗器械软件非诊断界定原则",
            ha='center', va='center', fontsize=7.5, color=NAVY)
    
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig1_2_data_privacy_compliance.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 1-3: 绿色边缘计算能耗与碳足迹对比图 (小作业1)
# ==============================================================================
def make_fig1_3():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4.5))
    fig.patch.set_facecolor("#FFFFFF")
    
    labels = ['传统全云端健康大模型\n(原始数据高频回传+持续推理)', '知衡端侧智能架构\n(本地稳健统计+轻量事实包)']
    
    # 1. 单用户每日计算能耗 (千焦 kJ)
    energy_cloud = 85.4
    energy_edge = 6.2
    bars1 = ax1.bar([0, 1], [energy_cloud, energy_edge], width=0.45, color=[CORAL, GREEN], edgecolor=NAVY, lw=1)
    ax1.set_ylabel("单用户单日计算能耗估算 (kJ)", fontsize=9.5, weight='bold', color=NAVY)
    ax1.set_xticks([0, 1])
    ax1.set_xticklabels(labels, fontsize=8.5)
    ax1.set_title("单日综合系统能耗对比\n(降幅高达 92.7%)", fontsize=11, weight='bold', color=NAVY)
    ax1.grid(axis='y', linestyle='--', alpha=0.5)
    for bar in bars1:
        yval = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2.0, yval + 2.5, f"{yval:.1f} kJ", ha='center', va='bottom', fontsize=9, weight='bold')
        
    # 2. 单用户年化碳排放 (kg CO2e) 与网络流量 (MB/月)
    carbon_cloud = 14.8
    carbon_edge = 1.2
    bars2 = ax2.bar([0, 1], [carbon_cloud, carbon_edge], width=0.45, color=[CORAL, TEAL], edgecolor=NAVY, lw=1)
    ax2.set_ylabel("单用户年化碳足迹估算 (kg CO₂e)", fontsize=9.5, weight='bold', color=NAVY)
    ax2.set_xticks([0, 1])
    ax2.set_xticklabels(labels, fontsize=8.5)
    ax2.set_title("年化碳排放对比与绿色计算\n(单用户年节碳 13.6 kg CO₂e)", fontsize=11, weight='bold', color=NAVY)
    ax2.grid(axis='y', linestyle='--', alpha=0.5)
    for bar in bars2:
        yval = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2.0, yval + 0.4, f"{yval:.1f} kg", ha='center', va='bottom', fontsize=9, weight='bold')

    plt.suptitle("图1-3 计算机工程环境可持续性对比：端侧协同方案 vs 传统云端大模型方案", fontsize=12, weight='bold', color=NAVY, y=0.98)
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig1_3_green_edge_carbon.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 2-1: 工程师社会责任与公众福祉闭环结构图 (小作业2)
# ==============================================================================
def make_fig2_1():
    fig, ax = plt.subplots(figsize=(9.5, 5.2))
    ax.set_facecolor(LIGHT_BG)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 6)
    ax.axis('off')
    
    ax.text(5, 5.6, "图2-1 计算机工程师职业伦理与公众福祉“四维责任守则”闭环", 
            ha='center', va='center', fontsize=13, weight='bold', color=NAVY)
    
    # 顶部核心准则框
    top_box = FancyBboxPatch((1.5, 4.3), 7.0, 0.9, boxstyle="round,pad=0.1", fc=NAVY, ec='none')
    ax.add_patch(top_box)
    ax.text(5, 4.75, "ACM / IEEE / CCF 计算机工程师职业伦理核心导向\n【公众福祉至上 (Public Good Above All) 与非伤害原则 (Do No Harm)】", 
            ha='center', va='center', fontsize=10, weight='bold', color='white')
    
    # 四大支柱责任
    columns = [
        ("公众安全防范责任", "• 设立紧急症状硬熔断\n• 杜绝伪医疗诊断与处方\n• 守护生命急救黄金窗口", CORAL, 0.4),
        ("心理健康与福祉责任", "• 反打卡成瘾与数字内耗\n• 采用低焦虑支持性交互\n• 消除虚假排名与同辈压力", TEAL, 2.75),
        ("数字普惠与无障碍责任", "• 适老化大字与高对比度\n• 消除穿戴设备算法偏见\n• 弥合健康管理数字鸿沟", ACCENT_BLUE, 5.1),
        ("绿色软件工程责任", "• 端侧确定性算法省电降耗\n• 减少无效数据轮询计算\n• 延长智能终端硬件寿命", GREEN, 7.45)
    ]
    
    for title, desc, col, x in columns:
        card = FancyBboxPatch((x, 1.4), 2.15, 2.4, boxstyle="round,pad=0.1", fc='white', ec=col, lw=1.5)
        ax.add_patch(card)
        ax.text(x + 1.07, 3.45, title, ha='center', va='center', fontsize=9.5, weight='bold', color=col)
        ax.text(x + 1.07, 2.4, desc, ha='center', va='center', fontsize=8, color=NAVY, linespacing=1.4)
        
        # 顶部下引箭头
        ax.annotate('', xy=(x + 1.07, 3.85), xytext=(x + 1.07, 4.3), 
                    arrowprops=dict(facecolor=NAVY, edgecolor='none', width=1.2, headwidth=5))
        # 底部下引箭头
        ax.annotate('', xy=(x + 1.07, 0.9), xytext=(x + 1.07, 1.35), 
                    arrowprops=dict(facecolor=col, edgecolor='none', width=1.2, headwidth=5))

    # 底部监督与反馈闭环
    bottom_box = FancyBboxPatch((1.5, 0.2), 7.0, 0.7, boxstyle="round,pad=0.1", fc=SLATE, ec='none')
    ax.add_patch(bottom_box)
    ax.text(5, 0.55, "全流程工程伦理审查机制：代码同行评审 + 极端场景测试 + 用户知情同意 + 持续社会影响后评估", 
            ha='center', va='center', fontsize=9, weight='bold', color='white')

    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig2_1_social_responsibility_loop.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 2-2: 多级安全防线与紧急医疗熔断机制 (小作业2)
# ==============================================================================
def make_fig2_2():
    fig, ax = plt.subplots(figsize=(9.5, 5.0))
    ax.set_facecolor("#FAFCFD")
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 5.5)
    ax.axis('off')
    
    ax.text(5, 5.1, "图2-2 智能健康工程全链路四道公众安全防线与医疗熔断逻辑", 
            ha='center', va='center', fontsize=12.5, weight='bold', color=NAVY)
    
    steps = [
        ("第一道防线：数据源合法性与防伪门禁", "缺失数据严禁补零；未佩戴/换设备明确标出；防止错误客观数据误导用户", TEAL, 4.0),
        ("第二道防线：致命症状与极端生理指标硬熔断", "监测到剧烈胸痛/严重心律失常/呼吸骤停 -> 立即阻断AI对话，强弹120与急救警示", CORAL, 2.9),
        ("第三道防线：确定性事实包白名单约束", "AI模型严禁直接读取底层原始样本；禁止凭空捏造病情，仅解释确定性统计结果", ACCENT_BLUE, 1.8),
        ("第四道防线：输出端低焦虑审核与免责门禁", "自动过滤恐吓性红色词汇；强制声明“非医疗器械/不可作为处方依据”底线", GREEN, 0.7)
    ]
    
    for title, desc, col, y in steps:
        box = FancyBboxPatch((0.8, y - 0.4), 8.4, 0.8, boxstyle="round,pad=0.1", fc="white", ec=col, lw=1.6)
        ax.add_patch(box)
        # 标签指示条
        tag = FancyBboxPatch((0.8, y - 0.4), 0.25, 0.8, boxstyle="round,pad=0.0", fc=col, ec='none')
        ax.add_patch(tag)
        
        ax.text(1.3, y + 0.15, title, ha='left', va='center', fontsize=10, weight='bold', color=col)
        ax.text(1.3, y - 0.18, desc, ha='left', va='center', fontsize=8.2, color=NAVY)
        
        if y > 0.8:
            ax.annotate('', xy=(5, y - 0.42), xytext=(5, y - 0.58), 
                        arrowprops=dict(facecolor=SLATE, edgecolor='none', width=1.5, headwidth=5))
            
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig2_2_safety_fuse_mechanism.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 3-1: 样机工程工作分解结构 (WBS) 四级树状图 (小作业3)
# ==============================================================================
def make_fig3_1():
    fig, ax = plt.subplots(figsize=(10.5, 5.8))
    ax.set_facecolor(LIGHT_BG)
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 6.5)
    ax.axis('off')
    
    ax.text(5.5, 6.1, "图3-1 “知衡”健康管理系统样机研发工作分解结构（WBS）", 
            ha='center', va='center', fontsize=13, weight='bold', color=NAVY)
    
    # 根节点 1.0
    root = FancyBboxPatch((4.0, 5.0), 3.0, 0.65, boxstyle="round,pad=0.1", fc=NAVY, ec='none')
    ax.add_patch(root)
    ax.text(5.5, 5.32, "1.0 知衡软件样机工程", ha='center', va='center', fontsize=10.5, weight='bold', color='white')
    
    # 二级节点
    branches = [
        ("1.1 需求与伦理合规", 1.0, 3.8, TEAL),
        ("1.2 端侧算法与存储", 3.25, 3.8, ACCENT_BLUE),
        ("1.3 前端交互与闭环", 5.5, 3.8, ORANGE),
        ("1.4 AI代理与事实包", 7.75, 3.8, CORAL),
        ("1.5 验证交付与总结", 9.8, 3.8, GREEN)
    ]
    
    sub_tasks = {
        0: ["1.1.1 需求工程调研", "1.1.2 个人信息合规论证", "1.1.3 软硬件边界定义"],
        1: ["1.2.1 HealthKit接入", "1.2.2 28天基线/MAD算法", "1.2.3 CareKit任务管道"],
        2: ["1.3.1 今日动态卡片", "1.3.2 微计划行动面板", "1.3.3 有效方法沉淀流"],
        3: ["1.4.1 事实包抽象序列化", "1.4.2 安全急救熔断器", "1.4.3 轻量API代理服务"],
        4: ["1.5.1 XCTest全量测试", "1.5.2 能耗/内存压测", "1.5.3 演示录屏与技术文档"]
    }
    
    for idx, (b_title, bx, by, col) in enumerate(branches):
        # 绘制分支节点
        b_box = FancyBboxPatch((bx - 0.9, by - 0.3), 1.8, 0.6, boxstyle="round,pad=0.08", fc=col, ec='none')
        ax.add_patch(b_box)
        ax.text(bx, by, b_title, ha='center', va='center', fontsize=8.5, weight='bold', color='white')
        
        # 连线从根节点到二级节点
        ax.plot([5.5, bx], [5.0, by + 0.35], color=SLATE, lw=1.2, ls='-')
        
        # 三级子任务
        tasks = sub_tasks[idx]
        for t_idx, t_name in enumerate(tasks):
            ty = by - 1.0 - t_idx * 0.7
            t_box = FancyBboxPatch((bx - 0.9, ty - 0.22), 1.8, 0.44, boxstyle="round,pad=0.05", fc='white', ec=CARD_BORDER, lw=0.9)
            ax.add_patch(t_box)
            ax.text(bx, ty, t_name, ha='center', va='center', fontsize=7.2, color=NAVY)
            # 垂直连线
            ax.plot([bx, bx], [by - 0.3, ty + 0.22], color=CARD_BORDER, lw=1, ls=':')

    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig3_1_wbs_structure.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 3-2: 样机敏捷迭代甘特图 (Gantt Chart) (小作业3)
# ==============================================================================
def make_fig3_2():
    tasks = [
        ("1. 需求调研与伦理合规论证", 1, 2.5, TEAL),
        ("2. 系统架构设计与技术栈选型", 2, 4, TEAL),
        ("3. HealthKit数据接入与基线算法", 3.5, 6.5, ACCENT_BLUE),
        ("4. CareKit微计划与数据持久化", 5, 8, ACCENT_BLUE),
        ("5. SwiftUI五标签用户界面开发", 6, 9.5, ORANGE),
        ("6. 事实包生成与云端AI Proxy代理", 7.5, 10, CORAL),
        ("7. 全面单元测试与能耗压力测试", 9, 11.5, GREEN),
        ("8. 样机集成评审、文档与成果交付", 10.5, 12, NAVY)
    ]
    
    fig, ax = plt.subplots(figsize=(10.5, 5.2))
    ax.set_facecolor("#FFFFFF")
    
    y_pos = np.arange(len(tasks))
    
    for idx, (t_name, start_w, end_w, col) in enumerate(tasks):
        duration = end_w - start_w
        # 绘制进度条
        ax.barh(idx, duration, left=start_w, height=0.45, align='center', color=col, alpha=0.9, edgecolor=NAVY, lw=0.8)
        ax.text(start_w + duration/2, idx, f"W{start_w}-W{end_w}", ha='center', va='center', color='white', fontsize=7.5, weight='bold')
        
    ax.set_yticks(y_pos)
    ax.set_yticklabels([t[0] for t in tasks], fontsize=8.8, color=NAVY)
    ax.invert_yaxis()  # 顶部从任务1开始
    
    ax.set_xlabel("研发项目周期进度 (周次 Week 1 - 12)", fontsize=10, weight='bold', color=NAVY)
    ax.set_xlim(0.5, 12.5)
    ax.set_xticks(range(1, 13))
    ax.set_xticklabels([f"W{i}" for i in range(1, 13)])
    ax.grid(axis='x', linestyle='--', alpha=0.6)
    
    # 标注重要里程碑
    milestones = [
        (2.5, "M1: 需求基线锁定", 0),
        (6.5, "M2: 核心算法闭环", 2),
        (10.0, "M3: 界面与AI联调完成", 5),
        (12.0, "M4: 样机全面验收通过", 7)
    ]
    for mx, mlabel, my in milestones:
        ax.plot(mx, my, marker='D', markersize=8, color=CORAL)
        ax.annotate(mlabel, xy=(mx, my), xytext=(mx + 0.2, my - 0.35),
                    fontsize=7.8, color=CORAL, weight='bold',
                    bbox=dict(boxstyle="round,pad=0.2", fc="#FFF3F0", ec=CORAL, lw=0.7))
        
    plt.title("图3-2 “知衡”样机研发工程 12 周敏捷迭代进度甘特图（含关键路径与里程碑）", fontsize=12, weight='bold', color=NAVY, pad=15)
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig3_2_project_gantt_chart.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 3-3: 样机研发经济成本核算结构饼图与柱状图 (小作业3)
# ==============================================================================
def make_fig3_3():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.8))
    fig.patch.set_facecolor("#FFFFFF")
    
    # 1. 成本占比饼图
    labels = [
        '直接人力成本\n(73.5%)', 
        '云算力与AI API\n(9.8%)', 
        '软硬件/测试机折旧\n(7.4%)', 
        '办公管理与工具\n(4.9%)', 
        '不可预见应急金\n(4.4%)'
    ]
    costs = [45000, 6000, 4500, 3000, 2700]
    colors = [TEAL, CORAL, ACCENT_BLUE, ORANGE, SLATE]
    explode = (0.05, 0.05, 0, 0, 0)
    
    wedges, texts, autotexts = ax1.pie(costs, explode=explode, labels=labels, autopct='%1.1f%%',
                                       startangle=140, colors=colors, textprops=dict(color=NAVY, fontsize=8))
    for at in autotexts:
        at.set_color('white')
        at.set_weight('bold')
        at.set_fontsize(8)
    ax1.set_title("样机全生命周期经济成本结构占比\n(总预算: 61,200 元)", fontsize=11, weight='bold', color=NAVY)
    
    # 2. 各细项费用金额柱状图
    items = [
        '研发人员工时折算\n(4人/3个月)',
        '大模型Token/云服务器\n(DeepSeek/ECS)',
        'Apple开发者/真机折旧\n(iPhone/Watch测试)',
        '协作工具与办公耗材\n(GitHub/Figma等)',
        '质量审查与应急储备\n(合规审计与备用金)'
    ]
    y_pos = np.arange(len(items))
    bars = ax2.barh(y_pos, costs, color=colors, edgecolor=NAVY, lw=0.8, height=0.55)
    ax2.set_yticks(y_pos)
    ax2.set_yticklabels(items, fontsize=8, color=NAVY)
    ax2.invert_yaxis()
    ax2.set_xlabel("预算核算金额 (元 RMB)", fontsize=9.5, weight='bold', color=NAVY)
    ax2.set_xlim(0, 52000)
    ax2.grid(axis='x', linestyle='--', alpha=0.6)
    
    for bar in bars:
        width = bar.get_width()
        ax2.text(width + 1000, bar.get_y() + bar.get_height()/2.0, f"¥{width:,}", ha='left', va='center', fontsize=8.5, weight='bold', color=NAVY)
        
    ax2.set_title("各分项工程预算核算明细柱状图", fontsize=11, weight='bold', color=NAVY)
    
    plt.suptitle("图3-3 “知衡”工程样机全生命周期经济成本科学核算分析图 (基于COCOMO II与TCO模型)", fontsize=12, weight='bold', color=NAVY, y=0.98)
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig3_3_cost_breakdown_pie.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

# ==============================================================================
# 图 3-4: 样机真实功能与运行界面多屏拼图 (小作业3)
# ==============================================================================
def make_fig3_4():
    # 尝试加载竞赛材料/应用方案图片/产品截图中的图片
    shots_dir = Path("/Users/chenweiyang/Documents/Project/竞赛材料/应用方案图片/产品截图")
    shot_files = ["01-today.png", "02-insights.png", "03-ai-assistant.png", "04-micro-plan-active.png"]
    
    loaded_imgs = []
    for sf in shot_files:
        p = shots_dir / sf
        if p.exists():
            loaded_imgs.append(Image.open(p))
            
    if len(loaded_imgs) == 4:
        # 拼接成 1行4列 或 2行2列
        # 统一缩放高度为 800px
        target_h = 700
        resized = []
        for img in loaded_imgs:
            w, h = img.size
            new_w = int(w * (target_h / h))
            resized.append(img.resize((new_w, target_h), Image.Resampling.LANCZOS))
            
        total_w = sum(img.size[0] for img in resized) + 60
        canvas_h = target_h + 120
        collage = Image.new("RGB", (total_w, canvas_h), "#F4F7F9")
        
        # 贴图
        curr_x = 20
        labels = ["【今日全景】\n生理与主观状态", "【可解释洞察】\n28天基线与趋势", "【AI健康助手】\n结构化事实包对话", "【CareKit微计划】\n低风险行动闭环"]
        
        # 绘制文本需要 matplotlib 绘制并保存
        fig, ax = plt.subplots(figsize=(11, 6))
        ax.set_facecolor(LIGHT_BG)
        ax.axis('off')
        
        # 在画布上并排放置4张图
        for i, (r_img, lbl) in enumerate(zip(resized, labels)):
            # 转换为 matplotlib array
            sub_ax = fig.add_axes([0.04 + i * 0.24, 0.12, 0.20, 0.72])
            sub_ax.imshow(r_img)
            sub_ax.axis('off')
            fig.text(0.14 + i * 0.24, 0.05, lbl, ha='center', va='center', fontsize=9, weight='bold', color=NAVY)
            
        fig.suptitle("图3-4 “知衡”系统样机真实功能闭环界面实景图（今日/洞察/AI助手/微计划）", fontsize=12, weight='bold', color=NAVY, y=0.95)
        out_path = OUTPUT_DIR / "fig3_4_prototype_showcase.png"
        plt.savefig(out_path, dpi=300)
        plt.close()
        print(f"已生成: {out_path.name}")
    else:
        print("未找到所有截图文件，跳过拼图生成")

# ==============================================================================
# 图 3-5: 样机敏捷冲刺燃尽图与自动化测试质量门禁演进图 (小作业3)
# ==============================================================================
def make_fig3_5():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.8))
    fig.patch.set_facecolor("#FFFFFF")
    
    # 1. 敏捷燃尽图 (Sprint Burndown Chart)
    sprints = np.array([0, 1, 2, 3, 4, 5, 6])
    weeks = ['启动', 'Sprint 1\n(W1-2)', 'Sprint 2\n(W3-4)', 'Sprint 3\n(W5-6)', 'Sprint 4\n(W7-8)', 'Sprint 5\n(W9-10)', 'Sprint 6\n(W11-12)']
    ideal_sp = np.array([120, 100, 80, 60, 40, 20, 0])
    actual_sp = np.array([120, 105, 84, 58, 36, 15, 0])
    
    ax1.plot(sprints, ideal_sp, '--', label='理想燃尽趋势 (Ideal)', color=SLATE, lw=1.8)
    ax1.plot(sprints, actual_sp, 'o-', label='实际燃尽消耗 (Actual)', color=TEAL, lw=2.4, markersize=6)
    ax1.fill_between(sprints, actual_sp, color=TEAL, alpha=0.15)
    
    for x, y in zip(sprints[1:], actual_sp[1:]):
        ax1.text(x, y + 3, f"{y} SP", ha='center', va='bottom', fontsize=8.2, weight='bold', color=TEAL)
        
    ax1.set_title("敏捷迭代故事点燃尽图 (Burndown Chart)", fontsize=11, weight='bold', color=NAVY)
    ax1.set_xlabel("研发迭代周期 (Sprint 1 ~ Sprint 6)", fontsize=9.5, weight='bold', color=NAVY)
    ax1.set_ylabel("剩余工作量故事点 (Story Points)", fontsize=9.5, weight='bold', color=NAVY)
    ax1.set_xticks(sprints)
    ax1.set_xticklabels(weeks, fontsize=8)
    ax1.set_ylim(-5, 135)
    ax1.grid(True, linestyle='--', alpha=0.5)
    ax1.legend(loc='upper right', fontsize=8.5)
    
    # 2. 测试用例数与代码覆盖率质量演进图
    test_cases = [0, 85, 192, 320, 445, 540, 606]
    coverage = [0, 65.2, 74.8, 83.5, 88.2, 90.6, 92.4]
    
    ax2_cov = ax2.twinx()
    bars = ax2.bar(sprints - 0.15, test_cases, width=0.3, color=ACCENT_BLUE, label='自动化测试用例总数 (个)', alpha=0.85, edgecolor=NAVY)
    line = ax2_cov.plot(sprints + 0.15, coverage, color=CORAL, marker='s', lw=2.2, label='核心逻辑代码覆盖率 (%)')
    
    ax2.set_title("样机质量门禁：测试套件规模与代码覆盖率演进", fontsize=11, weight='bold', color=NAVY)
    ax2.set_xlabel("研发迭代周期 (Sprint 1 ~ Sprint 6)", fontsize=9.5, weight='bold', color=NAVY)
    ax2.set_ylabel("自动化测试用例数 (个)", fontsize=9.5, weight='bold', color=ACCENT_BLUE)
    ax2_cov.set_ylabel("单元与集成测试覆盖率 (%)", fontsize=9.5, weight='bold', color=CORAL)
    
    ax2.set_xticks(sprints)
    ax2.set_xticklabels(weeks, fontsize=8)
    ax2.set_ylim(0, 800)
    ax2_cov.set_ylim(0, 115)
    ax2.grid(True, linestyle='--', alpha=0.5)
    
    # 最终测试用例标注 (584 iOS + 22 Proxy = 606)
    ax2.text(6 - 0.15, 480, "606项测试\n(584 iOS\n+22代理)", ha='center', va='center', fontsize=7.5, weight='bold', color='white')
    ax2_cov.text(6 + 0.15, 96.0, "覆盖率 92.4%", ha='center', va='bottom', fontsize=8.0, weight='bold', color=CORAL)
    
    # 合并图例
    lines_1, labels_1 = ax2.get_legend_handles_labels()
    lines_2, labels_2 = ax2_cov.get_legend_handles_labels()
    ax2.legend(lines_1 + lines_2, labels_1 + labels_2, loc='upper left', fontsize=8)
    
    plt.suptitle("图3-5 “知衡”样机敏捷冲刺燃尽分析与质量工程门禁度量演进图", fontsize=12, weight='bold', color=NAVY, y=0.98)
    plt.tight_layout()
    out_path = OUTPUT_DIR / "fig3_5_burndown_and_quality.png"
    plt.savefig(out_path)
    plt.close()
    print(f"已生成: {out_path.name}")

if __name__ == '__main__':
    make_fig1_1()
    make_fig1_2()
    make_fig1_3()
    make_fig2_1()
    make_fig2_2()
    make_fig3_1()
    make_fig3_2()
    make_fig3_3()
    make_fig3_4()
    make_fig3_5()
    print("全部图表生成完毕！保存于:", OUTPUT_DIR)
