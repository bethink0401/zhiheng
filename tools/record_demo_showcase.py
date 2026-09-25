#!/usr/bin/env python3
import os
import signal
import subprocess
import time

DEVICE = "D0662F58-FF9D-4BC1-8827-7C97640C0981"
BUNDLE_ID = "com.zhiheng.healthassistant.a21f7c9d"
OUTPUT_PATH = "/Users/chenweiyang/Documents/Project/竞赛材料/知衡软件功能演示录屏.mp4"

print("1. 终止正在运行的旧实例...")
subprocess.run(["xcrun", "simctl", "terminate", DEVICE, BUNDLE_ID], capture_output=True)
time.sleep(1)

print(f"2. 启动录屏进程: {OUTPUT_PATH}")
record_proc = subprocess.Popen([
    "xcrun", "simctl", "io", DEVICE, "recordVideo",
    "--codec=h264", "--force", OUTPUT_PATH
])

# 等待录屏初始化
time.sleep(2)

print("3. 启动知衡 App (全自动演示模式)...")
launch_proc = subprocess.run([
    "xcrun", "simctl", "launch", DEVICE, BUNDLE_ID,
    "-healthDataMode", "demo",
    "--demo-showcase-recording"
], capture_output=True, text=True)
print(f"启动状态: {launch_proc.stdout.strip()}")

timeline = [
    (0, "【乐章一：今日态势与主客观打卡】展示活动圆环与16项生理指标卡片"),
    (4, "【今日页】平滑滚动至主观状态区，唤起每日感受打卡面板"),
    (8, "【打卡交互】调节精力、压力、身体感受分值，展示生活情境备注输入"),
    (14, "【主客对照】打卡完成并收起面板，展示今日状态卡片即时更新主客观对照"),
    (30, "【乐章二：可解释洞察与深度溯源】切换至洞察页，呈现HRV云朵背景与日内参考带"),
    (35, "【数据依据】展开HRV详情面板：28天个人基线、7天移动均值、26/28有效天数与93%覆盖率"),
    (44, "【指标总览】收起详情面板，平滑向下滚动浏览16项身体指标与趋势"),
    (58, "【乐章三：健康智能体深度推理】切换至AI助手，启动动态打字机提出微计划诉求"),
    (64, "【事实包提取】发送请求，智能体消费脱敏事实包并展示思考流"),
    (68, "【主动追问】智能体结构化输出事实与可能因素，主动发起关键追问（昨晚入睡时间）"),
    (74, "【用户应答】用户回复晚睡情况，智能体接收反馈并进行二次协同分析"),
    (80, "【安全门禁与微计划】通过本地非诊断安全校验，生成建议微计划候选卡片（早睡30分钟，连续5天）"),
    (118, "【乐章四：CareKit 行动闭环与复盘】切换至微计划，展示行动日程与每日完成记录"),
    (126, "【四维评估】平滑滚动至计划评估卡片：客观趋势、主观感受、80%完成率与数据质量四维复盘"),
    (138, "【趋势观察】平滑滚动至计划期指标对比曲线与历史归档"),
    (148, "【乐章五：我的有效方法沉淀库】切换至有效方法，展示多次计划沉淀的4档可信度方法卡"),
    (154, "【维度筛选】交互演示：动态筛选【睡眠】维度关联方法"),
    (159, "【维度筛选】交互演示：动态筛选【压力】维度关联方法"),
    (164, "【全量库】交互演示：切回【全部】方法，展示重新发起独立验证能力"),
    (172, "【乐章六：全流程闭环】切回今日主页，完成健康洞察与行动管理闭环"),
    (178, "演示演出完毕，准备停止录屏并封装视频文件...")
]

start_time = time.time()
for target_s, desc in timeline:
    now = time.time() - start_time
    wait_s = max(0.0, target_s - now)
    time.sleep(wait_s)
    cur = int(time.time() - start_time)
    print(f"[{cur:02d}s] {desc}")

time.sleep(3)
print("4. 发送 SIGINT 结束录屏并写入文件...")
record_proc.send_signal(signal.SIGINT)
try:
    record_proc.wait(timeout=15)
except subprocess.TimeoutExpired:
    record_proc.kill()

if os.path.exists(OUTPUT_PATH):
    size_mb = os.path.getsize(OUTPUT_PATH) / (1024 * 1024)
    print(f"✅ 录屏成功完成！文件大小: {size_mb:.2f} MB，路径: {OUTPUT_PATH}")
else:
    print("❌ 录屏文件未生成！")
