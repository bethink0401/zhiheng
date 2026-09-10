from pathlib import Path
from PIL import Image as PILImage, ImageOps
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Image
from docx import Document
from docx.shared import Cm
from docx.enum.section import WD_SECTION

ROOT = Path(__file__).resolve().parent
PDF_OUT = ROOT.parent / "output" / "pdf" / "知衡国创赛项目计划书完整版.pdf"
WORD_OUT = ROOT.parent / "output" / "word" / "知衡国创赛项目计划书完整版.docx"
PAGES = ROOT / "artifacts" / "zhiheng-book-pages"
ASSETS = ROOT / "assets"
LOGO = ROOT.parent / "Design" / "AppIcon-Zhiheng-v3-focus-liquid-glass.png"
FONT_FILE = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
FONT = "ArialUnicode"
INK = colors.HexColor("#171717")
MID = colors.HexColor("#5B5B5B")
LIGHT = colors.HexColor("#F1F1F1")
LINE = colors.HexColor("#4C4C4C")
pdfmetrics.registerFont(TTFont(FONT, FONT_FILE))

S = {
    "cover": ParagraphStyle("cover", fontName=FONT, fontSize=29, leading=39, textColor=INK, alignment=TA_CENTER),
    "cover_sub": ParagraphStyle("cover_sub", fontName=FONT, fontSize=15, leading=23, textColor=MID, alignment=TA_CENTER),
    "title": ParagraphStyle("title", fontName=FONT, fontSize=18, leading=25, textColor=INK, spaceAfter=10, keepWithNext=True),
    "h2": ParagraphStyle("h2", fontName=FONT, fontSize=12.2, leading=18, textColor=INK, spaceBefore=7, spaceAfter=5, keepWithNext=True),
    "body": ParagraphStyle("body", fontName=FONT, fontSize=9.6, leading=16.2, textColor=INK, alignment=TA_JUSTIFY, spaceAfter=7),
    "small": ParagraphStyle("small", fontName=FONT, fontSize=7.7, leading=11, textColor=MID),
    "table": ParagraphStyle("table", fontName=FONT, fontSize=8.3, leading=12, textColor=INK),
    "tableh": ParagraphStyle("tableh", fontName=FONT, fontSize=8.3, leading=12, textColor=INK, alignment=TA_CENTER),
    "quote": ParagraphStyle("quote", fontName=FONT, fontSize=11.4, leading=18, textColor=INK, alignment=TA_CENTER),
}


def p(text, style="body"):
    return Paragraph(text, S[style])


def three_line(headers, rows, widths):
    data = [[p(x, "tableh") for x in headers]] + [[p(str(x), "table") for x in row] for row in rows]
    t = Table(data, colWidths=widths, hAlign="LEFT", repeatRows=1)
    n = len(data) - 1
    t.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, 0), 0.9, LINE),
        ("LINEBELOW", (0, 0), (-1, 0), 0.55, LINE),
        ("LINEBELOW", (0, n), (-1, n), 0.9, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("BACKGROUND", (0, 0), (-1, 0), LIGHT),
    ]))
    return t


def bullet(text):
    return Paragraph("•  " + text, ParagraphStyle("b", parent=S["body"], leftIndent=13, firstLineIndent=-9, spaceAfter=3))


def callout(title, text):
    box = Table([[p("<b>" + title + "</b>  " + text, "body")]], colWidths=[16.8 * cm])
    box.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), LIGHT),
        ("LINEBEFORE", (0, 0), (0, -1), 2.5, INK),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return box


def flow(labels):
    return p("　→　".join(["<b>" + x + "</b>" for x in labels]), "quote")


def page_head(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINE); canvas.setLineWidth(.4)
    canvas.line(2 * cm, 28.35 * cm, 19 * cm, 28.35 * cm)
    canvas.setFillColor(MID); canvas.setFont(FONT, 7.5)
    canvas.drawString(2 * cm, 28.58 * cm, "知衡｜国创赛项目计划书")
    canvas.drawRightString(19 * cm, 1.18 * cm, "非诊疗健康管理与生活方式改善工具")
    canvas.drawCentredString(10.5 * cm, 1.18 * cm, str(doc.page))
    canvas.restoreState()


def page(title, elements):
    return [p(title, "title"), Spacer(1, .10 * cm)] + elements + [PageBreak()]


def chart_bar(labels, values, title):
    from reportlab.graphics.shapes import Drawing, Rect, String, Line
    d = Drawing(480, 188)
    d.add(String(0, 169, title, fontName=FONT, fontSize=10, fillColor=INK))
    d.add(Line(44, 24, 465, 24, strokeColor=LINE, strokeWidth=.8))
    maxv = max(values)
    step = 380 / len(labels)
    for i, (label, v) in enumerate(zip(labels, values)):
        h = 118 * v / maxv
        x = 65 + i * step
        d.add(Rect(x, 24, 42, h, fillColor=colors.HexColor("#4B4B4B"), strokeColor=None))
        d.add(String(x + 6, 28 + h, str(v) + "%", fontName=FONT, fontSize=8, fillColor=INK))
        d.add(String(x - 5, 7, label, fontName=FONT, fontSize=8, fillColor=MID))
    return d


def chart_timeline():
    from reportlab.graphics.shapes import Drawing, Line, Circle, String
    d = Drawing(480, 140)
    d.add(Line(36, 72, 450, 72, strokeColor=INK, strokeWidth=1.1))
    data = [(55, "2026.07", "产品架构\n与数据边界"), (158, "2026.08", "洞察、AI、\n微计划闭环"), (262, "2026.09", "计划书、\n用户验证"), (366, "2026.10", "稳定性、\n答辩材料")]
    for x, date, text in data:
        d.add(Circle(x, 72, 5.5, fillColor=INK, strokeColor=INK))
        d.add(String(x - 20, 94, date, fontName=FONT, fontSize=8.5, fillColor=INK))
        for j, line in enumerate(text.split("\n")):
            d.add(String(x - 27, 42 - j * 12, line, fontName=FONT, fontSize=8, fillColor=MID))
    return d


def as_gray(source, destination):
    im = PILImage.open(source).convert("L")
    im.save(destination)


def product_pair(left, right, captions):
    lgray, rgray = ASSETS / (left.stem + "-gray.png"), ASSETS / (right.stem + "-gray.png")
    as_gray(left, lgray); as_gray(right, rgray)
    data = [[Image(str(lgray), width=6.1 * cm, height=13.25 * cm), Image(str(rgray), width=6.1 * cm, height=13.25 * cm)],
            [p(captions[0], "small"), p(captions[1], "small")]]
    t = Table(data, colWidths=[8.35 * cm, 8.35 * cm], hAlign="CENTER")
    t.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    return t


def build_pdf():
    PDF_OUT.parent.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    st = []
    st += [Spacer(1, 2.4 * cm)]
    if LOGO.exists(): st += [Image(str(LOGO), width=3.15 * cm, height=3.15 * cm, hAlign="CENTER"), Spacer(1, .45 * cm)]
    st += [p("国创赛项目计划书", "cover_sub"), Spacer(1, .25 * cm), p("知 衡", "cover"), Spacer(1, .25 * cm), p("从健康洞察到行为改变的 AI 个人健康智能体", "cover_sub"), Spacer(1, 1.25 * cm)]
    st += [three_line(["项目名称", "参赛团队信息"], [("知衡——从健康洞察到行为改变的AI个人健康智能体", "西南科技大学｜负责人：陈维阳"), ("项目类型", "AI个人健康智能服务平台"), ("团队成员", "李思磊、杜浩天、陈风博弈、张潼心、王奥"), ("版本", "V2.0｜2026年9月")], [8.3 * cm, 8.5 * cm]), Spacer(1, .8 * cm), p("把健康数据变成可理解、可执行、可验证的个人方法资产", "quote"), PageBreak()]
    st += page("目录", [p("01 项目摘要　02 问题与机会　03 用户与调研设计　04 产品方案　05 产品展示　06 技术与AI安全", "body"), p("07 核心创新　08 竞品与竞争策略　09 市场路径　10 研发基础　11 实施计划　12 团队与社会价值　13 附录与来源", "body"), callout("阅读说明", "本计划书采用黑白视觉和三线表呈现；所有产品页面均为本项目演示模式截图。行业、竞品资料以公开官方材料为依据；尚未完成的用户问卷、访谈和商业数据均明确标注为“拟验证”，不虚构为已取得成果。")])
    st += page("01｜项目摘要", [p("知衡是一款面向成年用户的AI个人健康智能体。项目将运动、睡眠、心率等多维健康记录，与精力、压力、身体感受和生活情境连接起来，通过数据质量判断、个人基线建模、趋势识别和AI解释，帮助用户理解近期状态并选择一个可承担的下一步行动。", "body"), p("知衡的关键不是“多一个数据面板”，而是建立“发现变化—理解变化—尝试行动—验证效果—沉淀方法”的长期闭环。系统优先与用户过去的自己比较，避免用统一阈值简单评价不同生活方式的人；数据不足、来源变化或单日异常时，系统会诚实提示继续观察。", "body"), flow(["可信数据", "个体洞察", "微行动", "效果验证", "方法资产"]), three_line(["用户问题", "知衡的回答"], [("最近为什么感觉状态不佳？", "在数据质量门槛内，展示相对个人基线的变化与相关情境。"), ("我现在能做什么？", "一次提供一个3—7天、低风险、可随时停止的微计划。"), ("这个方法适合我吗？", "结合完成率、主观反馈、趋势和数据质量形成审慎评估。")], [5 * cm, 11.8 * cm])])
    st += page("02｜使命、愿景与边界", [p("使命：让健康数据不再只是难以理解的图表，而成为用户认识自己、改善生活方式并持续积累个人经验的能力。", "body"), p("愿景：推动健康管理进入AI个体化时代，让每个人都拥有一个长期陪伴、持续学习、尊重差异的健康智能体。", "body"), three_line(["坚持什么", "不做什么"], [("个人基线优先：主要比较用户与过去的自己", "不把单一指标或综合分数等同于健康结论"), ("主观感受与客观记录并列", "不否定用户感受，不把相关性写成因果"), ("低风险、可停止的微行动", "不做疾病诊断、治疗、处方或急救监护"), ("隐私优先与可追溯AI", "不出售健康画像，不将原始记录用于广告")], [8.4 * cm, 8.4 * cm]), callout("核心定位", "知衡属于健康管理和生活方式改善工具。它提供的是趋势解释、健康教育和低风险行动引导，而不是医疗建议或疾病判断。")])
    st += page("03｜行业背景与问题机会", [p("随着智能穿戴和健康数据平台普及，用户能够获得越来越多的运动、睡眠与生理记录；但“数据增加”没有自动转化为“理解增加”。公开健康资料显示，2022年全球约31%的成年人未达到推荐身体活动水平，健康行为的长期坚持仍是一项广泛挑战。", "body"), chart_bar(["达到推荐", "未达到推荐"], [69, 31], "全球成年人身体活动水平（2022，公开统计）"), p("资料来源：世界卫生组织（WHO）《Physical activity》事实清单，2024年6月更新。图表为对公开比例的再绘制，仅用于说明宏观健康行为挑战。", "small"), three_line(["当前常见体验", "用户没有被解决的问题"], [("指标分散、图表复杂", "不同数据之间有什么关联、哪些值得关注？"), ("统一目标与短期打卡", "这个目标是否适合我当下的作息与状态？"), ("泛化健康建议", "我可以先尝试什么低负担行动？"), ("缺少执行后评估", "这次改变究竟有没有可能帮助到我？")], [6.2 * cm, 10.6 * cm])])
    st += page("04｜目标用户与典型场景", [three_line(["重点用户", "高频情境", "知衡价值"], [("大学生", "考试、项目、竞赛导致作息波动", "识别睡眠、精力与活动变化，形成轻量改善方案"), ("青年职场人", "久坐、加班、高压力", "将状态与生活情境转化为可坚持的微行动"), ("运动入门用户", "习惯建立与恢复观察", "避免单日波动误导，支持逐步验证"), ("睡眠困扰人群", "作息不稳、日间精力下降", "提供趋势观察和低风险生活方式尝试"), ("关注家庭健康者", "共同关注生活方式", "逐步形成可回顾的健康经验")], [3.2 * cm, 5.4 * cm, 8.2 * cm]), p("优先聚焦成年用户。项目第一阶段不针对儿童、孕产期、复杂慢病治疗、术后康复或持续医学监护设计。", "body")])
    st += page("05｜用户调研设计与公开资料验证", [p("为避免“凭想象做产品”，知衡将采用公开资料梳理、半结构化访谈、可用性测试与短期日记研究结合的方式。以下为拟执行的调研方案；在取得真实样本之前，项目不会把假设性结论包装成调研结论。", "body"), three_line(["研究模块", "拟定方法", "拟回答的问题"], [("公开资料验证", "WHO健康行为资料、穿戴设备与健康平台官方功能资料", "健康行为长期坚持与数据解读的宏观挑战"), ("需求访谈", "招募8—12名成年用户，45分钟半结构化访谈", "用户如何理解数据、何时产生焦虑、愿意尝试什么行动"), ("问卷筛选", "30—50名成年用户，收集使用频率、主要困惑与隐私顾虑", "目标人群特征与场景优先级"), ("可用性测试", "5—8名用户使用演示模式完成任务", "能否理解“数据不足”、洞察与微计划"), ("日记研究", "5—7天记录感受、情境与行动反馈", "主客观记录如何形成可信闭环")], [3.4 * cm, 6.1 * cm, 7.3 * cm]), callout("当前状态", "本版计划书只引用公开资料与官方竞品资料；“真实用户样本数、比例、访谈原话、满意度”均待执行后补充。")])
    st += page("06｜用户旅程：从困惑到方法", [flow(["数据积累", "发现变化", "理解状态", "微计划", "效果回看"]), three_line(["阶段", "用户感受", "知衡的支持"], [("日常记录", "有很多记录，但不确定哪些重要", "整合可用数据并先检查数据质量"), ("状态变化", "觉得疲劳或睡眠不好，却说不清原因", "提示与个人基线相比的长期变化，而非单日判断"), ("获得解释", "需要理解，不想被恐吓", "AI区分事实、可能因素和不确定性"), ("尝试行动", "大计划难坚持", "只推荐一个3—7天低风险微计划"), ("回顾效果", "不知道改变是否有意义", "以完成率、感受、趋势和数据质量共同评估")], [3 * cm, 6 * cm, 7.8 * cm]), callout("体验原则", "减少“你应该怎样”的说教，更多回答“基于你自己的长期记录，什么值得观察、什么值得尝试”。")])
    st += page("07｜产品闭环与功能地图", [p("知衡的产品结构围绕“洞察到行为改变”设计。数据、算法、主观感受、AI和行动记录均有清晰职责，避免让AI自由读取原始数据或让页面直接给出未经验证的健康结论。", "body"), flow(["数据接入", "质量判断", "个人基线", "趋势洞察", "AI解释", "微计划", "评估沉淀"]), three_line(["功能模块", "为用户提供", "差异化"], [("今日", "近期状态与明确的演示/真实数据标识", "不使用恐吓式单一健康评分"), ("洞察", "与个人近期参考的趋势和解释", "数据质量先于趋势"), ("主观记录", "精力、压力、身体感受和情境", "主客观信息同等重要"), ("AI助手", "基于事实包的解释与最多一个追问", "AI回答可追溯、有边界"), ("微计划", "可开始、暂停、恢复和结束的行动", "一次一个、低风险、可随时停止"), ("有效方法", "回看多次行动后可能有效的经验", "把一次性建议变成个人方法资产")], [3.1 * cm, 6 * cm, 7.7 * cm])])
    home, insight, plan_img, ai_img = [ASSETS / x for x in ["zhiheng-home.png", "zhiheng-insights.png", "zhiheng-plan.png", "zhiheng-ai.png"]]
    st += page("08｜产品展示：今日与洞察", [product_pair(home, insight, ("图1：今日页。演示数据标识清晰，状态、数据质量与“今日变化”集中呈现。", "图2：洞察页。以个人近期参考解释多项指标，不将其描述为医学正常范围。")), p("以上均为知衡项目演示模式截图。页面使用演示数据，不包含真实个人健康记录；本页已按黑白计划书规范转换为灰度图。", "small")])
    st += page("09｜产品展示：微计划与AI助手", [product_pair(plan_img, ai_img, ("图3：微计划页。用户在AI助手中确认候选计划后才进入行动闭环。", "图4：AI助手页。问题围绕授权数据、趋势和低风险微计划展开。")), p("AI承担解释与行动引导角色，不替代本地趋势计算；用户确认前不自动写入计划。", "small")])
    st += page("10｜个人基线与数据质量守门", [p("知衡不将“群体平均值”直接作为判断用户状态的唯一依据。系统在最近28天、至少14个有效日的前提下形成个人基线，并在最近7天、至少4个有效日的前提下判断短期变化。缺失记录不按0处理，单日异常不直接形成趋势。", "body"), three_line(["质量信号", "系统处理", "表达方式"], [("有效日不足", "不计算强趋势，保留数据状态", "数据不足，建议继续观察"), ("设备未使用/记录断档", "识别缺失，避免误判下降", "记录不完整，暂不下结论"), ("来源变化", "标记来源变化，不与历史直接混比", "数据来源发生变化"), ("单日异常", "使用中位数、MAD等稳健方法降低影响", "单日波动不代表持续变化"), ("趋势满足门槛", "保存时间范围、样本数、覆盖率和阈值版本", "存在持续变化，值得继续观察")], [3.6 * cm, 7.1 * cm, 6.1 * cm]), callout("算法原则", "固定输入产生固定输出；本地程序负责计算事实，AI只对结构化事实做解释。")])
    st += page("11｜AI健康洞察：事实受控、输出可追溯", [flow(["聚合事实", "安全预检", "AI解释", "客户端校验", "用户确认"]), p("知衡采用“本地确定性分析＋受控AI解释”技术路线。AI不会直接读取全部原始记录，而是接收完成回答所需的最小化聚合事实包：时间范围、数据质量、基线与当前值、程序计算的趋势、用户主动提供的感受与情境，以及允许推荐的低风险计划模板。", "body"), three_line(["输出层", "要求"], [("事实", "只能引用事实包中已有的时间范围、趋势和数据质量"), ("可能因素", "使用可能、也许、值得观察等不确定表达，不写确定因果"), ("行动建议", "最多一个低风险、3—7天、可随时停止的微计划"), ("安全边界", "拒绝诊断、处方、停药和剂量调整；紧急症状优先提示及时求助"), ("失败降级", "网络或模型失败时保留本地规则摘要，不伪造AI结论")], [4.1 * cm, 12.7 * cm])])
    st += page("12｜核心创新一：从群体标准到个人基线", [p("同一数值在不同人的作息、体能、训练习惯和生活阶段中可能意味着不同的背景。知衡以用户自身长期记录建立动态基线，优先比较“现在的我”与“过去的我”，而不是用一个固定标准衡量所有人。", "body"), three_line(["传统做法", "知衡做法", "用户收益"], [("用统一阈值触发提醒", "结合有效日、个人中位数与离散程度判断变化", "减少不符合自身情境的误判"), ("关注某一天的极值", "看7天窗口相对28天基线的稳健变化", "降低偶然波动带来的焦虑"), ("数据单独展示", "把趋势、感受和情境共同呈现", "获得更贴近真实生活的解释")], [5.2 * cm, 6.1 * cm, 5.5 * cm]), p("这种差异使知衡能够把“看到一个数字”升级为“理解自己的变化”。", "quote")])
    st += page("13｜核心创新二：主客观融合与生活情境", [p("健康不是只有设备记录。用户的精力、压力、身体感受、差旅、考试、项目冲刺、运动调整等生活情境，往往是理解数据变化的重要背景。知衡以少量、低负担的记录补足这些背景，并始终尊重用户主观感受。", "body"), three_line(["客观信息", "主观信息", "融合后的表达"], [("运动、睡眠、心率等趋势", "精力、压力、身体感受", "客观记录与感受同步变化，值得继续观察"), ("数据看似稳定", "用户持续感觉不佳", "尊重感受，建议补充情境或寻求专业帮助"), ("数据不足", "用户有明确生活事件", "不强行解释，用情境帮助用户回顾")], [5.3 * cm, 5.3 * cm, 6.2 * cm]), callout("低焦虑表达", "知衡不使用“你不健康”“指标危险”等恐吓文案；当证据不足时，优先承认不知道。")])
    st += page("14｜核心创新三：微计划与行动验证", [p("宏大的健康目标常常难以落实。知衡每次洞察只推荐一个低风险、3—7天、可随时停止的微计划，例如调整睡前节律、午后步行、减少久坐或适度降低运动负荷。用户确认后才开始，且可以暂停、恢复或提前结束。", "body"), three_line(["计划阶段", "系统记录", "不做的事"], [("开始", "计划类型、周期与计划开始前的聚合基线快照", "不保存原始健康样本，不自动替用户开始"), ("执行", "完成/跳过与可选简短感受", "不以强制打卡制造压力"), ("结束", "完成率、主观反馈、客观趋势与数据质量", "不把一次结果称为“证明有效”"), ("沉淀", "多次方向一致后形成个人方法线索", "不把相关变化视为治疗效果")], [3 * cm, 7.6 * cm, 6.2 * cm])])
    st += page("15｜竞品格局与差异化策略", [p("竞品研究基于公开官方资料与产品可见功能，用于识别定位差异，不对第三方产品的算法、隐私实现或医疗能力作未经证实的判断。", "body"), three_line(["产品类别/代表", "公开可见重点", "知衡的策略"], [("智能穿戴平台（如 Garmin Connect）", "训练、活动与健康数据的记录、趋势与统计", "在数据展示基础上，强化个人基线、感受情境与行动验证"), ("健康教练型服务（如 Fitbit）", "健康目标、习惯培养、指导内容与个性化服务", "聚焦“事实—解释—微计划—评估”的可追溯闭环"), ("通用AI问答", "自然语言交流与泛化建议", "以本地结构化事实包约束回答，避免脱离真实数据"), ("数据看板类工具", "单项指标、历史图表与提醒", "不止展示指标，沉淀用户自己的有效方法")], [4 * cm, 5.8 * cm, 7 * cm]), p("资料来源：Garmin Connect 官方产品页；Google/Fitbit 官方博客关于个人健康教练与Premium服务的说明；访问日期：2026年9月1日。完整链接见附录。", "small")])
    st += page("16｜竞争壁垒：不是AI聊天，而是可验证系统", [three_line(["壁垒层", "形成机制"], [("数据壁垒", "个人基线、数据质量、趋势、时间范围和情境持续积累，形成用户专属健康画像。"), ("算法壁垒", "本地稳健统计与质量门槛先行，减少单日噪声和来源变化造成的错误解释。"), ("交互壁垒", "事实、解释、建议分层；一次只推进一个小行动，降低认知与执行负担。"), ("行为壁垒", "通过计划执行、主观反馈和趋势评估，让用户形成自己的方法资产。"), ("信任壁垒", "最小化数据、非诊疗边界、可追溯AI与低焦虑表达，建立长期使用基础。")], [4.2 * cm, 12.6 * cm]), callout("竞争判断", "知衡的护城河来自闭环协同，而非某一个单点功能：只有当数据质量、个人基线、情境、AI解释、行动记录与效果评估共同运行，用户才能积累真正属于自己的健康方法。")])
    st += page("17｜市场进入路径与服务设想", [p("项目先从高频、高压力、愿意尝试数字健康工具的大学生与青年职场人切入，验证“看懂变化—愿意行动—能够坚持—愿意回看”的产品价值，再按照设备、数据平台和服务场景逐步拓展。", "body"), three_line(["阶段", "目标", "主要动作"], [("校园验证", "验证核心闭环可理解、低焦虑、可执行", "招募成年用户，开展可用性测试和短期日记研究"), ("场景深化", "聚焦睡眠、久坐、运动恢复与压力场景", "完善微计划模板与效果评估规则"), ("多设备拓展", "降低设备与平台边界", "研究授权、数据口径与质量规则的分级适配"), ("组织服务探索", "探索校园、企业与社区健康促进", "在用户授权和隐私前提下提供服务化能力")], [3 * cm, 5.7 * cm, 8.1 * cm]), p("商业模式以用户价值验证为先。长期可探索基础功能免费、进阶分析与个性化服务增值、以及面向组织的健康促进服务；不以出售健康数据、健康广告或夸大医疗能力作为商业路径。", "body")])
    st += page("18｜研发基础与工程进度", [p("截至2026年9月1日，知衡已建立移动端工程、演示数据适配、健康数据读取、个人基线与趋势、主观记录、可解释洞察、AI流式对话、微计划执行、计划开始基线快照和结束评估等能力。项目已完成模拟器交互和构建验证。", "body"), chart_timeline(), three_line(["能力模块", "当前完成基础", "下一步"], [("数据与洞察", "多类数据映射、数据质量、7/28天趋势、个人基线", "继续进行真实数据与多来源验证"), ("AI", "结构化事实包、流式对话、输出校验、安全边界", "继续验证断网、超时和真实环境"), ("微计划", "十类低风险模板、执行反馈、暂停恢复、结束评估", "完成更新、跨天、删除与历史一致性"), ("产品体验", "今日、洞察、微计划、AI助手、我的五个主要页面", "开展可理解性与低焦虑体验测试")], [3.2 * cm, 7.5 * cm, 6.1 * cm]), p("工程验证说明：项目记录显示162项iOS测试与14项AI代理测试已通过；该结果代表当前软件工程测试，不等同于临床验证或大规模用户验证。", "small")])
    st += page("19｜实施计划与里程碑", [three_line(["时间", "关键任务", "预期产出"], [("2026年9月", "完善计划更新、跨天、删除与历史一致性；完成可用性测试准备", "稳定演示版本与用户测试任务脚本"), ("2026年10月", "开展首轮成年用户可用性测试、整理反馈、修复关键理解问题", "需求优先级、可用性证据与迭代清单"), ("2026年11月", "完成比赛材料、演示脚本、答辩问答和原创性说明", "可提交的申报书、PPT、演示材料"), ("后续", "研究多设备接入、数据口径与更多生活方式场景", "阶段化平台拓展路线")], [3 * cm, 8.1 * cm, 5.7 * cm]), callout("执行原则", "先完成一个可验证闭环，再扩展更多功能；先用真实用户验证理解与行为，再讨论规模化。")])
    st += page("20｜团队与职责", [p("团队来自西南科技大学，采用产品、技术、研究与表达协同推进模式。负责人统筹产品定位、研发节奏与比赛表达；成员围绕研发、用户研究、设计展示和运营验证形成明确分工。具体个人专业与指导教师信息可按学校模板补充。", "body"), three_line(["成员", "建议职责"], [("陈维阳（负责人）", "项目总体推进、产品战略、技术路线协调、答辩与资源统筹"), ("李思磊", "产品需求、用户研究、访谈与可用性测试组织"), ("杜浩天", "移动端研发、健康数据与计划闭环实现"), ("陈风博弈", "AI能力、数据分析、服务与安全验证"), ("张潼心", "交互设计、视觉表达、产品演示与材料整理"), ("王奥", "竞品研究、市场路径、运营与项目管理支持")], [4.5 * cm, 12.3 * cm]), callout("协作机制", "每周形成“用户反馈—产品问题—技术验证—材料表达”闭环，确保比赛叙事来源于真实产品能力与可核验材料。")])
    st += page("21｜社会价值、隐私与伦理", [three_line(["价值方向", "项目贡献"], [("健康素养", "帮助普通用户理解个人健康数据及其不确定性，降低单一数字带来的焦虑。"), ("行为改善", "将抽象健康目标拆分为可执行、可评估的低负担微行动。"), ("可信AI", "用事实包、结构化输出和安全校验约束AI健康交互。"), ("隐私保护", "本地优先、最小必要、用户授权与删除能力，减少敏感数据暴露。"), ("普惠服务", "后续探索校园、企业和社区的健康促进场景。")], [4.2 * cm, 12.6 * cm]), p("项目坚持：不提供疾病诊断、处方、药物剂量调整或持续急救监护；不把单项数据直接等同于疾病；不把数据不足伪装成确定结论；紧急症状优先提示及时寻求当地急救或专业帮助。", "body")])
    st += page("22｜风险识别与应对", [three_line(["风险", "可能影响", "应对措施"], [("数据不完整或设备差异", "误判变化、体验不稳定", "质量守门；缺失不按0；分阶段适配不同数据来源"), ("AI编造或过度推断", "用户信任与健康安全风险", "结构化事实包、输出校验、本地降级与固定安全测试"), ("医疗边界模糊", "产生不当健康依赖", "非诊疗定位、低风险建议、紧急症状安全提示"), ("隐私风险", "敏感信息泄露", "本地优先、最小化数据、授权和删除能力"), ("范围过大", "研发资源分散", "聚焦洞察—行动—评估核心闭环，分阶段扩展")], [3.8 * cm, 5 * cm, 8 * cm]), callout("风险观", "可信健康产品的第一原则不是给出更多结论，而是在证据不足、AI失败和用户不适时保持克制、可解释和安全。")])
    st += page("23｜知识产权与原创性说明", [p("知衡以个人基线、数据质量守门、主客观融合、事实受控AI、微计划行动验证与“我的有效方法”构成原创的产品闭环。项目参考公开技术资料与开源框架的通用能力边界，但不以更名、换界面方式复用他人完整产品、交互或提示词。", "body"), three_line(["类别", "处理原则"], [("原创部分", "个人基线与趋势表达、数据质量规则、主客观对照、计划效果评估、方法资产与低焦虑交互。"), ("开源与技术参考", "记录来源、许可证、版本与用途；严格区分“参考”“依法复用”“不采用”。"), ("竞品资料", "只使用公开、可访问的官方资料进行功能观察，不对未公开实现作推断。"), ("后续保护", "根据实际研发成果与学校要求，评估软件著作权、专利或其他知识产权申请。")], [4.3 * cm, 12.5 * cm])])
    st += page("24｜结语", [Spacer(1, 1.4 * cm), p("知衡不是又一个展示健康数据的应用。", "cover_sub"), Spacer(1, .3 * cm), p("它要让每一次健康记录，都更接近一次对自己的理解；让每一次低风险尝试，都有机会成为真正适合自己的方法。", "cover_sub"), Spacer(1, 1.3 * cm), callout("一句话项目定义", "知衡是一个以AI为驱动、从个人健康洞察走向行为改变的健康智能体：把数据转成理解，把理解转成行动，把行动沉淀成个人方法。"), Spacer(1, .8 * cm), p("西南科技大学｜知衡项目团队", "quote")])
    st += page("附录A｜公开资料与竞品来源", [p("以下来源用于本项目行业背景和竞品功能观察。访问日期均为2026年9月1日；若提交系统要求参考文献格式，建议按学校模板统一调整。", "body"), three_line(["编号", "资料来源", "用途"], [("[1]", "World Health Organization. Physical activity. https://www.who.int/news-room/fact-sheets/detail/physical-activity", "全球成年人身体活动不足比例与健康行为背景"), ("[2]", "Garmin Connect. https://connect.garmin.com/", "智能穿戴数据记录、分析与趋势呈现的公开功能观察"), ("[3]", "Google / Fitbit Blog. Fitbit launches Fitbit Premium. https://blog.google/products-and-platforms/devices/fitbit/fitbit-launches-fitbit-premium/", "健康习惯、指导与个性化服务的公开功能观察"), ("[4]", "Google / Fitbit Blog. New Fitbit personal health coach features. https://blog.google/products-and-platforms/devices/fitbit/fitbit-personal-health-coach-new-features/", "AI健康教练与个性化交互的公开功能观察")], [1.1 * cm, 11.4 * cm, 4.3 * cm]), p("产品截图来源：知衡项目演示模式，由项目团队于2026年9月1日在模拟器环境截取；全部为演示数据。", "small")])
    st += page("附录B｜最终提交前核验清单", [three_line(["材料", "提交前核验"], [("团队与学校", "已确认学校、赛道、负责人、成员、指导教师与联系方式"), ("用户调研", "已真实开展的样本、时间、方法、发现与原始记录可追溯；未完成则保留“拟开展”表述"), ("产品演示", "截图、录屏和演示数据均脱敏，明确不含真实个人健康信息"), ("竞品与行业数据", "每个数字和功能判断均有可访问来源及引用日期"), ("知识产权与合作", "只填写已获得的软著、专利、合作、订单、融资或获奖证明"), ("财务材料", "所有收入、成本、市场规模和预测均有可复查计算依据"), ("安全与合规", "非诊疗边界、隐私说明、紧急症状提示与开源声明完整")], [4.5 * cm, 12.3 * cm]), callout("提交原则", "真实、可核验、可追溯，比夸大的用户量、收入或医疗效果更有说服力。")])
    if isinstance(st[-1], PageBreak): st.pop()
    doc = SimpleDocTemplate(str(PDF_OUT), pagesize=A4, leftMargin=2*cm, rightMargin=2*cm, topMargin=2.45*cm, bottomMargin=2*cm, title="知衡国创赛项目计划书完整版", author="西南科技大学知衡项目团队")
    doc.build(st, onFirstPage=page_head, onLaterPages=page_head)


def build_word():
    import subprocess
    PAGES.mkdir(parents=True, exist_ok=True)
    subprocess.run(["pdftoppm", "-png", "-r", "150", str(PDF_OUT), str(PAGES / "page")], check=True)
    imgs = sorted(PAGES.glob("page-*.png"), key=lambda x: int(x.stem.split("-")[-1]))
    WORD_OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = Document()
    section = doc.sections[0]
    section.page_width, section.page_height = Cm(21), Cm(29.7)
    section.top_margin = section.bottom_margin = Cm(.35)
    section.left_margin = section.right_margin = Cm(.45)
    for i, img in enumerate(imgs):
        para = doc.add_paragraph()
        para.alignment = 1
        para.paragraph_format.space_before = para.paragraph_format.space_after = 0
        para.add_run().add_picture(str(img), width=Cm(19.5), height=Cm(27.58))
        if i != len(imgs) - 1:
            doc.add_page_break()
    doc.core_properties.title = "知衡国创赛项目计划书完整版"
    doc.core_properties.author = "西南科技大学知衡项目团队"
    doc.save(WORD_OUT)


if __name__ == "__main__":
    build_pdf(); build_word(); print(WORD_OUT)
