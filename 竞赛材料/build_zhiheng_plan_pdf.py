from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image, KeepTogether
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "output" / "pdf" / "知衡国创赛项目计划书.pdf"
LOGO = ROOT.parent / "Design" / "AppIcon-Zhiheng-v3-focus-liquid-glass.png"

pdfmetrics.registerFont(TTFont("ArialUnicode", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"))
FONT = "ArialUnicode"
INK = colors.HexColor("#153B4D")
BLUE = colors.HexColor("#176B87")
TEAL = colors.HexColor("#15A7A0")
PALE = colors.HexColor("#F4F8FA")
LIGHT = colors.HexColor("#EAF6F5")
GRID = colors.HexColor("#D8E3E7")


def styles():
    return {
        "cover_kicker": ParagraphStyle("cover_kicker", fontName=FONT, fontSize=13, leading=20, textColor=TEAL, alignment=TA_CENTER, spaceAfter=10),
        "cover_title": ParagraphStyle("cover_title", fontName=FONT, fontSize=28, leading=38, textColor=INK, alignment=TA_CENTER, spaceAfter=4),
        "cover_subtitle": ParagraphStyle("cover_subtitle", fontName=FONT, fontSize=17, leading=26, textColor=BLUE, alignment=TA_CENTER, spaceAfter=20),
        "cover_tagline": ParagraphStyle("cover_tagline", fontName=FONT, fontSize=11, leading=18, textColor=colors.HexColor("#60707A"), alignment=TA_CENTER),
        "h1": ParagraphStyle("h1", fontName=FONT, fontSize=17, leading=25, textColor=BLUE, spaceBefore=13, spaceAfter=10, keepWithNext=True),
        "h2": ParagraphStyle("h2", fontName=FONT, fontSize=13, leading=20, textColor=INK, spaceBefore=10, spaceAfter=6, keepWithNext=True),
        "body": ParagraphStyle("body", fontName=FONT, fontSize=10.5, leading=18, textColor=colors.HexColor("#263640"), alignment=TA_JUSTIFY, spaceAfter=8),
        "small": ParagraphStyle("small", fontName=FONT, fontSize=8.8, leading=13, textColor=colors.HexColor("#60707A"), alignment=TA_CENTER),
        "table": ParagraphStyle("table", fontName=FONT, fontSize=8.7, leading=13, textColor=colors.HexColor("#263640")),
        "table_head": ParagraphStyle("table_head", fontName=FONT, fontSize=9, leading=13, textColor=colors.white, alignment=TA_CENTER),
        "callout_title": ParagraphStyle("callout_title", fontName=FONT, fontSize=10.5, leading=15, textColor=INK, spaceAfter=3),
        "callout_body": ParagraphStyle("callout_body", fontName=FONT, fontSize=10, leading=16, textColor=INK),
        "toc": ParagraphStyle("toc", fontName=FONT, fontSize=11, leading=21, textColor=INK),
    }


S = styles()


def p(text, style="body"):
    return Paragraph(text, S[style])


def table(headers, rows, widths):
    data = [[p(h, "table_head") for h in headers]]
    for row in rows:
        data.append([p(str(cell), "table") for cell in row])
    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), INK),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("GRID", (0, 0), (-1, -1), 0.45, GRID),
        ("BACKGROUND", (0, 1), (-1, -1), colors.white),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, PALE]),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    return t


def callout(title, body):
    t = Table([[p("<b>" + title + "</b>", "callout_title"), p(body, "callout_body")]], colWidths=[2.2 * cm, 14.2 * cm], hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), LIGHT),
        ("LINEBEFORE", (0, 0), (0, -1), 3, TEAL),
        ("BOX", (0, 0), (-1, -1), 0.6, TEAL),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 9),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
    ]))
    return t


def flow(labels):
    text = '<font color="#153B4D">' + '</font><font color="#15A7A0">  →  </font><font color="#153B4D">'.join(labels) + "</font>"
    style = ParagraphStyle("flow", fontName=FONT, fontSize=10.5, leading=18, textColor=INK, alignment=TA_CENTER, spaceBefore=3, spaceAfter=12)
    return Paragraph(text, style)


def bullet(text):
    return Paragraph("•  " + text, ParagraphStyle("bullet", parent=S["body"], leftIndent=14, firstLineIndent=-10, spaceAfter=4))


def page_deco(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(GRID)
    canvas.setLineWidth(0.35)
    canvas.line(2 * cm, 28.7 * cm, 19 * cm, 28.7 * cm)
    canvas.setFont(FONT, 8)
    canvas.setFillColor(colors.HexColor("#60707A"))
    canvas.drawString(2 * cm, 28.95 * cm, "知衡  |  国创赛项目计划书")
    canvas.drawRightString(19 * cm, 1.35 * cm, "健康数据用于理解与行动，不用于诊断或治疗")
    canvas.drawCentredString(10.5 * cm, 1.35 * cm, str(doc.page))
    canvas.restoreState()


def story():
    out = []
    out.append(Spacer(1, 2.6 * cm))
    if LOGO.exists():
        out.append(Image(str(LOGO), width=3.1 * cm, height=3.1 * cm, hAlign="CENTER"))
        out.append(Spacer(1, 0.45 * cm))
    out += [p("国创赛项目计划书", "cover_kicker"), p("知衡", "cover_title"), p("从健康洞察到行为改变的AI个人健康智能体", "cover_subtitle"), p("让健康数据转化为每个人可理解、可执行、可验证的有效方法", "cover_tagline"), Spacer(1, 1.1 * cm)]
    out.append(table(["项目名称", "参赛信息"], [
        ("项目名称", "知衡——从健康洞察到行为改变的AI个人健康智能体"),
        ("参赛赛道", "高教主赛道（请按学校最终通知填写）"),
        ("申报单位", "【待填写：学校名称】"),
        ("项目团队", "【待填写：负责人、成员及指导教师】"),
    ], [3.2 * cm, 13.2 * cm]))
    out += [Spacer(1, 0.7 * cm), p("版本：V1.0  |  日期：2026年9月1日", "small"), PageBreak()]
    out += [p("目录", "cover_title"), Spacer(1, 0.6 * cm)]
    for item in ["01 项目摘要", "02 行业背景与用户痛点", "03 产品方案与使用场景", "04 核心创新与竞争优势", "05 技术路线与AI安全", "06 市场定位与商业模式", "07 项目进展与实施计划", "08 团队建设与资源需求", "09 社会价值、风险与合规", "10 附录：提交前待补材料清单"]:
        out.append(p(item, "toc"))
    out += [Spacer(1, 0.35 * cm), callout("使用说明", "本稿已使用现有产品事实与项目定位撰写。方括号中的学校、团队、调研、合作、知识产权及财务数据须由团队补充后再提交；未完成事项均以计划表述，不应替换为既有成果。"), PageBreak()]

    out += [p("01  项目摘要", "h1"), p("知衡是一款从健康洞察走向行为改变的AI个人健康智能体。面对健康数据持续增长而用户仍然看不懂、用不好、坚持不下去的痛点，知衡将多维健康数据与用户的精力、压力、身体感受和生活情境连接起来，通过数据质量判断、个人基线建模、趋势识别和AI解释，帮助用户理解近期值得关注的变化。"), p("知衡不止记录数据，而是构建“发现变化、理解变化、采取行动、验证效果、沉淀方法”的完整闭环。系统在每次洞察后只推荐一个三至七天、低风险、可随时停止的微计划；计划结束后，结合完成率、主观反馈、客观趋势和数据质量，形成审慎结论，并逐步沉淀用户专属的有效方法库。"), callout("项目使命", "让健康数据不再只是图表中的数字，而成为帮助用户理解自己、改善生活方式、持续积累个人健康方法的能力。"), p("项目价值主张", "h2"), flow(["可信数据", "个体洞察", "微行动", "效果验证", "个人方法资产"]), table(["用户得到什么", "知衡如何实现"], [("看懂近期变化", "用个人基线与趋势识别替代单纯指标展示"), ("获得低负担行动", "一次只给出一个三至七天、低风险的微计划"), ("知道是否适合自己", "综合完成率、主观感受、趋势与数据质量进行评估"), ("长期形成健康经验", "将多次验证后的结果沉淀为个人有效方法库")], [5.2 * cm, 11.2 * cm])]

    out += [p("02  行业背景与用户痛点", "h1"), p("智能穿戴设备和健康数据平台正在让运动、睡眠、心率等信息更容易被记录，但“记录更多”并不等于“理解更多”。用户常常面对分散的图表、统一的目标和短期的打卡任务，仍难以回答自己最关心的三个问题：最近发生了什么，我可以如何改善，以及这种方法是否真的适合我。"), p("四类关键痛点", "h2")]
    for x in ["数据碎片化：指标分散在不同页面，用户难以形成完整的自我理解。", "群体标准化：统一阈值忽视不同作息、体能和生活方式造成的个体差异。", "建议同质化：泛化的建议难以转化为持续行动。", "缺少验证闭环：用户完成行动后，通常无法判断是偶然波动还是值得保留的方法。"]:
        out.append(bullet(x))
    out += [callout("核心问题", "如何把长期健康数据转化为可信、低焦虑、可执行、可验证的个人健康行动。"), p("目标用户与优先场景", "h2"), table(["优先用户", "典型场景", "知衡提供的价值"], [("大学生", "考试、竞赛、作息波动", "帮助识别睡眠与精力变化，形成轻量改善方案"), ("青年职场人", "久坐、加班、高压力", "将日常状态和生活情境转化为可坚持的微行动"), ("运动入门用户", "训练恢复、习惯建立", "避免单日数据误导，支持观察与低风险调整"), ("关注家庭健康的成年人", "共同关注作息与生活方式", "沉淀长期、个体化的健康经验")], [3 * cm, 5.2 * cm, 8.2 * cm])]

    out += [p("03  产品方案与使用场景", "h1"), p("产品闭环", "h2"), flow(["授权连接", "数据质量", "个人基线", "AI洞察", "微计划", "效果评估", "有效方法"]), p("知衡在分析前先判断数据是否足以支持结论。对于数据缺失、来源变化、异常波动或设备未使用等情况，系统优先提示“数据不足”或“建议继续观察”，而不是强行输出结论。只有当近期有效数据与个人基线共同满足条件时，才生成值得继续观察的变化。"), p("核心功能", "h2"), table(["功能模块", "用户体验", "差异化价值"], [("健康数据总览", "查看近期状态与关键记录", "不以单一健康分数定义用户"), ("个人基线与趋势", "理解自己与过去的自己相比发生了什么", "以长期有效数据建立动态个人参考"), ("主观与情境记录", "快速记录精力、压力、身体感受和生活事件", "让客观数据与真实感受共同参与分析"), ("AI健康洞察", "获得事实、可能因素、不确定性与下一步建议", "AI只解释结构化健康事实，不自由编造数据"), ("微计划", "执行一个低风险、可停止的三至七天行动", "降低复杂计划与打卡挫败感"), ("我的有效方法", "回顾什么情境下什么方法可能有帮助", "把一次性建议转化为长期个人资产")], [3 * cm, 6 * cm, 7.4 * cm]), p("典型用户故事", "h2"), p("一名准备比赛的学生发现自己连续数日睡眠时长相较于个人近期基线出现变化，同时记录了较高压力和晚间咖啡情境。知衡不会断言原因，而是说明已观察到的事实、提示可能相关因素与其他可能性，并建议尝试一个短期微计划。计划结束后，系统结合执行情况、主观精力与可用数据趋势给出审慎的本地评估。用户由此获得的不是抽象建议，而是一条可以继续验证的个人经验。")]

    out += [p("04  核心创新与竞争优势", "h1"), p("五项核心创新", "h2"), table(["创新点", "创新说明"], [("个人基线引擎", "主要比较用户与过去的自己，降低统一标准对个体差异的误判。"), ("数据质量守门", "先识别有效天数、缺失、异常和来源变化，再决定是否输出洞察。"), ("主客观融合", "把用户感受和生活情境与客观数据并列，不让设备数据否定人的体验。"), ("AI解释与微计划闭环", "AI在事实边界内解释趋势并引导一个低风险行动，而不是泛化说教。"), ("个人有效方法资产", "通过多次行动与评估，沉淀可回看、可复用、可继续验证的方法库。")], [4.5 * cm, 11.9 * cm]), p("与常见产品类别的差异", "h2"), table(["对比维度", "数据展示类应用", "通用AI问答", "知衡"], [("健康数据处理", "以图表和单项指标为主", "依赖用户描述", "数据质量与个人基线先行"), ("健康解释", "有限或固定", "可能脱离真实数据", "基于结构化事实包与时间范围"), ("行动建议", "统一目标或打卡", "临时建议", "一次一个可停止的微计划"), ("效果验证", "通常缺失", "通常缺失", "完成率、感受、趋势和数据质量共同评估"), ("长期价值", "历史图表", "一次性对话", "个人有效方法库")], [3.1 * cm, 4.3 * cm, 4.1 * cm, 4.9 * cm]), callout("竞争壁垒", "知衡的竞争力不在于增加一个AI聊天入口，而在于把个人基线、数据质量、生活情境、行动记录和效果验证连接为一个可追溯的长期系统。")]

    out += [p("05  技术路线与AI安全", "h1"), p("技术路线", "h2"), flow(["数据接入", "本地清洗", "趋势计算", "健康事实包", "安全规则", "AI解释", "客户端校验"]), p("知衡采用“本地确定性分析加受控AI解释”的技术路线。数据质量、个人基线、趋势结果和计划评估由可测试的本地规则生成；AI只使用完成回答所必需的聚合事实，用于解释、追问和行动引导。这样既发挥AI的自然语言交互能力，也保留数据依据和可追溯性。"), p("数据与AI边界", "h2"), table(["环节", "设计原则", "用户价值"], [("数据处理", "本地优先，只使用实现当前功能所需的数据", "减少敏感数据暴露"), ("事实包", "仅发送时间范围、聚合趋势、数据质量与用户主动提供的信息", "AI回答有明确依据"), ("AI输出", "区分事实、可能因素、不确定性、一个追问和建议行动", "避免把相关性写成因果"), ("安全规则", "识别诊断、药物和紧急症状请求并优先安全处理", "明确非诊疗边界"), ("失败降级", "网络或模型失败时保留本地规则摘要", "核心体验不依赖AI在线可用")], [3 * cm, 8.2 * cm, 5.2 * cm]), p("安全与隐私承诺", "h2")]
    for x in ["不提供疾病诊断、处方、药物剂量调整或持续急救监护。", "不将单项指标直接等同于压力、恢复能力或疾病。", "不将健康数据用于广告、出售画像或训练基础模型。", "原始健康数据默认不上传；用户可查看权限状态并删除相关记录。", "当用户主动描述紧急症状时，优先提示及时寻求当地急救或专业帮助。"]:
        out.append(bullet(x))

    out += [p("06  市场定位与商业模式", "h1"), p("市场定位", "h2"), p("知衡定位于个人健康管理和生活方式改善，而非诊疗服务。项目以成年个人用户为起点，先在高频、高压力、对数据理解有明确需求的学习与工作场景中验证价值，再逐步探索家庭、校园、企业与社区健康促进场景。"), p("阶段化服务路径", "h2"), table(["阶段", "重点用户与场景", "核心目标"], [("第一阶段", "大学生与青年职场人", "验证健康洞察、微计划和有效方法闭环"), ("第二阶段", "睡眠、运动恢复、久坐和压力管理场景", "扩展可验证的健康行为改善模板"), ("第三阶段", "家庭、校园、企业和社区", "探索群体健康促进与服务协同"), ("长期", "多设备与多健康数据平台", "形成开放、可信的个人健康服务网络")], [3 * cm, 7 * cm, 6.4 * cm]), p("商业模式设想", "h2"), p("项目当前以产品验证和用户价值验证为优先。长期可采用基础功能免费、进阶分析与个性化服务增值的模式，并探索面向校园和企业的健康促进服务。任何商业化均以用户授权、隐私保护和不影响健康建议独立性为前提，不以出售健康数据或健康广告为核心收入来源。"), callout("提交提醒", "若学校要求填写营收、融资或市场规模，必须使用团队可提供的可核验材料和明确出处；本计划书不虚构订单、用户量、合作协议或收入。")]

    out += [p("07  项目进展与实施计划", "h1"), p("当前开发基础", "h2"), p("截至2026年9月1日，项目已建立移动端产品工程、健康数据读取与演示数据适配、个人基线与趋势、主观记录、可解释洞察、AI流式对话、微计划执行、计划开始基线快照和结束评估等核心能力。项目已完成模拟器交互与构建验证，并通过162项iOS测试和14项AI代理测试。上述数字代表当前工程测试结果，不等同于临床验证或大规模用户验证。"), table(["模块", "已完成的核心能力", "下一步重点"], [("数据与洞察", "多类健康数据映射、数据质量、个人基线、7天与28天趋势", "继续完成真实数据与多来源验证"), ("AI能力", "结构化事实包、流式对话、输出校验和安全边界", "完善断网与真实环境验证"), ("行动闭环", "十类低风险模板、计划执行、反馈、暂停恢复、结束评估", "补齐计划更新、跨天、删除与历史一致性"), ("产品体验", "今日、洞察、微计划、AI助手、我的五个主要页面", "开展可理解性与低焦虑体验测试")], [3 * cm, 8.1 * cm, 5.3 * cm]), p("后续实施里程碑", "h2"), table(["阶段", "关键工作", "预期产出"], [("产品稳定", "完善计划历史一致性、异常处理与演示模式", "可稳定演示的核心闭环"), ("用户验证", "招募首轮成年用户，观察理解度、行动意愿与焦虑反馈", "需求与可用性证据"), ("比赛打磨", "完成计划书、演示脚本、答辩材料和原创性说明", "完整参赛材料"), ("生态拓展", "研究更多设备、数据平台与场景的接入路径", "跨设备平台化路线图")], [3 * cm, 8 * cm, 5.4 * cm])]

    out += [p("08  团队建设与资源需求", "h1"), p("团队分工", "h2"), table(["角色", "主要职责", "团队成员"], [("项目负责人", "产品定位、整体推进、答辩与资源协调", "【待填写】"), ("产品与设计", "用户研究、交互设计、视觉与内容表达", "【待填写】"), ("技术研发", "健康数据、算法、AI、客户端与服务端开发", "【待填写】"), ("市场与运营", "用户访谈、试点组织、竞品与推广策略", "【待填写】"), ("指导资源", "健康安全、创新创业、技术与赛事指导", "【待填写】")], [3 * cm, 8.8 * cm, 4.6 * cm]), p("所需资源", "h2"), p("项目后续需要用户测试招募、健康安全文案审阅、智能穿戴与健康数据平台适配测试、云端AI调用与安全服务、比赛展示设备及校内创新创业资源支持。团队将优先使用低成本、可验证的方式推进，不以未经验证的大规模投入替代产品验证。")]

    out += [p("09  社会价值、风险与合规", "h1"), p("社会价值", "h2"), table(["价值方向", "知衡的贡献"], [("健康素养", "帮助普通用户理解个人健康数据与不确定性，而非被单项数字驱动焦虑。"), ("行为改善", "将大而空泛的健康目标拆解为低负担、可执行、可评估的微行动。"), ("可信AI", "以事实包、结构化输出与安全校验约束AI健康交互。"), ("健康公平", "探索面向校园、企业和社区的普惠健康促进服务。")], [4.1 * cm, 12.3 * cm]), p("主要风险与应对", "h2"), table(["风险", "应对方案"], [("数据不足或设备差异", "数据质量守门；数据不足时不输出强结论；后续分阶段适配更多设备与数据平台。"), ("AI编造或过度推断", "结构化事实包、输出校验、本地规则降级和固定安全测试集。"), ("医疗误导", "坚持非诊疗定位、低风险建议与紧急症状优先安全提示。"), ("隐私泄露", "本地优先、最小必要数据、明确授权与删除能力。"), ("项目范围过大", "聚焦“洞察到行为改变”闭环，按阶段验证后再扩展。")], [4.5 * cm, 11.9 * cm]), callout("合规底线", "知衡的价值建立在可信与克制之上：数据不足时诚实说明，相关性不写成因果，不将AI回答包装为诊断或治疗。")]

    out += [p("10  附录：提交前待补材料清单", "h1"), p("以下材料应由团队在最终提交前补齐。没有证据的内容不要写成已完成成果。")]
    for x in ["学校名称、参赛赛道、负责人、团队成员、指导教师和联系方式。", "产品截图、演示视频链接或二维码，并确保全部使用演示数据或完成脱敏。", "用户访谈或测试记录，包括样本数、时间、方法和主要发现。", "竞品调研来源、行业数据来源和引用日期。", "软著、专利、论文、获奖、合作或媒体报道等证明材料，如确实拥有。", "预算、资金来源与财务预测的计算依据，如学校提交模板要求。", "开源参考、许可证与知衡原创部分说明。", "健康安全文案审阅记录，或明确标注尚未完成专业审阅。"]:
        out.append(bullet("待补：" + x))
    out += [Spacer(1, 0.3 * cm), callout("团队答辩可使用的一句话", "知衡不是又一个展示健康数据的应用，而是一个把个人健康数据转化为可解释洞察、低风险行动和可验证个人方法的AI健康智能体。")]
    return out


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, rightMargin=2 * cm, leftMargin=2 * cm, topMargin=2.35 * cm, bottomMargin=2 * cm, title="知衡国创赛项目计划书", author="知衡项目团队")
    doc.build(story(), onFirstPage=page_deco, onLaterPages=page_deco)
    print(OUT)


if __name__ == "__main__":
    main()
