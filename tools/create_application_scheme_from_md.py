#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION_START
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


BLACK = "000000"
LIGHT_GRAY = "D9D9D9"
BODY_FONT = "STFangsong"
HEADING_FONT = "STHeiti"
SUBHEADING_FONT = "STHeiti"
TITLE_FONT = "STSong"


def set_run_font(run, font_name: str, size: float | None = None, bold: bool | None = None):
    run.font.name = font_name
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), font_name)
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:ascii"), font_name)
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:hAnsi"), font_name)
    run.font.color.rgb = RGBColor(0, 0, 0)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold


def set_cell_margins(cell, top=90, start=90, bottom=90, end=90):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcMar = tcPr.first_child_found_in("w:tcMar")
    if tcMar is None:
        tcMar = OxmlElement("w:tcMar")
        tcPr.append(tcMar)
    for m, v in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tcMar.find(qn(f"w:{m}"))
        if node is None:
            node = OxmlElement(f"w:{m}")
            tcMar.append(node)
        node.set(qn("w:w"), str(v))
        node.set(qn("w:type"), "dxa")


def set_table_borders(table, color=LIGHT_GRAY, size="4"):
    tblPr = table._tbl.tblPr
    borders = tblPr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tblPr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = qn(f"w:{edge}")
        node = borders.find(tag)
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), size)
        node.set(qn("w:space"), "0")
        node.set(qn("w:color"), color)


def set_table_no_borders(table):
    tblPr = table._tbl.tblPr
    borders = tblPr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tblPr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        node = borders.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), "nil")


def set_cell_bottom_border(cell, color=BLACK, size="8"):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = tcPr.find(qn("w:tcBorders"))
    if borders is None:
        borders = OxmlElement("w:tcBorders")
        tcPr.append(borders)
    bottom = borders.find(qn("w:bottom"))
    if bottom is None:
        bottom = OxmlElement("w:bottom")
        borders.append(bottom)
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), size)
    bottom.set(qn("w:space"), "0")
    bottom.set(qn("w:color"), color)


def set_three_line_borders(table):
    tblPr = table._tbl.tblPr
    borders = tblPr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tblPr.append(borders)
    settings = {
        "top": ("single", "10", BLACK),
        "bottom": ("single", "10", BLACK),
        "left": ("nil", "0", BLACK),
        "right": ("nil", "0", BLACK),
        "insideH": ("nil", "0", BLACK),
        "insideV": ("nil", "0", BLACK),
    }
    for edge, (val, size, color) in settings.items():
        node = borders.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), val)
        node.set(qn("w:sz"), size)
        node.set(qn("w:space"), "0")
        node.set(qn("w:color"), color)


def shade_cell(cell, fill: str):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = tcPr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tcPr.append(shd)
    shd.set(qn("w:fill"), fill)


def add_page_field(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = "1"
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend([begin, instr, separate, text, end])
    set_run_font(run, HEADING_FONT, 8.5)


def set_page_number_start(section, value: int):
    sectPr = section._sectPr
    pg = sectPr.find(qn("w:pgNumType"))
    if pg is None:
        pg = OxmlElement("w:pgNumType")
        sectPr.append(pg)
    pg.set(qn("w:start"), str(value))


def parse_markdown(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    title = ""
    sections = []
    current = None
    paragraph_lines = []

    def flush_paragraph():
        nonlocal paragraph_lines
        if current is not None and paragraph_lines:
            current["paragraphs"].append("".join(s.strip() for s in paragraph_lines).strip())
        paragraph_lines = []

    for line in lines:
        if line.startswith("# ") and not title:
            title = line[2:].strip().replace("“", "").replace("”", "")
        elif line.startswith("## "):
            flush_paragraph()
            current = {"heading": line[3:].strip(), "paragraphs": []}
            sections.append(current)
        elif not line.strip():
            flush_paragraph()
        else:
            paragraph_lines.append(line)
    flush_paragraph()
    return title, sections


SUBHEADS = {
    1: {0: "时代变化与现实需求", 2: "项目定位与平台愿景"},
    2: {0: "数据理解与个体差异", 2: "情境连接与行动缺口"},
    3: {0: "可信洞察需求", 2: "行动闭环与安全需求"},
    4: {0: "核心用户", 3: "扩展场景与服务边界"},
    6: {0: "移动端与数据技术", 2: "AI服务与工程保障"},
    7: {0: "系统分层架构", 1: "本地可信分析", 2: "受控AI推理", 3: "行动与评估闭环"},
    8: {0: "今日与洞悉", 2: "AI助手与情境记录", 4: "微计划与有效方法", 6: "历史报告与隐私"},
    9: {0: "首次使用", 1: "日常洞察与AI交互", 3: "计划执行与个人控制"},
    10: {0: "AI核心引擎", 1: "双引擎协作", 2: "建议验证与安全机制"},
    11: {0: "个人应用空间", 1: "多场景与平台化前景"},
    12: {0: "个人订阅服务", 1: "专业与机构服务", 3: "商业化原则"},
    13: {0: "竞争差异", 1: "核心优势"},
    14: {0: "技术与工程可行性", 2: "分阶段落地", 3: "合规与长期路径"},
    15: {0: "数据与AI风险", 2: "医疗、隐私与商业风险"},
    16: {0: "个人健康价值", 2: "行业与社会价值"},
    17: {0: "近期与中期规划", 2: "长期平台方向"},
    18: {0: "产品与技术成果", 2: "用户价值成果"},
}


def add_alt_text(inline_shape, title: str, description: str):
    doc_pr = inline_shape._inline.docPr
    doc_pr.set("title", title)
    doc_pr.set("descr", description)


def add_bookmark(paragraph, name: str, bookmark_id: int):
    start = OxmlElement("w:bookmarkStart")
    start.set(qn("w:id"), str(bookmark_id))
    start.set(qn("w:name"), name)
    end = OxmlElement("w:bookmarkEnd")
    end.set(qn("w:id"), str(bookmark_id))
    paragraph._p.insert(0, start)
    paragraph._p.append(end)


def append_internal_hyperlink(paragraph, anchor: str, text: str, size=10.2):
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("w:anchor"), anchor)
    hyperlink.set(qn("w:history"), "1")
    run = OxmlElement("w:r")
    rpr = OxmlElement("w:rPr")
    color = OxmlElement("w:color")
    color.set(qn("w:val"), BLACK)
    rfonts = OxmlElement("w:rFonts")
    rfonts.set(qn("w:eastAsia"), BODY_FONT)
    rfonts.set(qn("w:ascii"), BODY_FONT)
    rfonts.set(qn("w:hAnsi"), BODY_FONT)
    size_el = OxmlElement("w:sz")
    size_el.set(qn("w:val"), str(int(size * 2)))
    rpr.extend([rfonts, color, size_el])
    text_el = OxmlElement("w:t")
    text_el.text = text
    run.extend([rpr, text_el])
    hyperlink.append(run)
    paragraph._p.append(hyperlink)


def add_caption(doc: Document, text: str):
    p = doc.add_paragraph(style="Caption")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = False
    run = p.add_run(text)
    set_run_font(run, BODY_FONT, 8.5)
    return p


def add_wide_figure(doc: Document, image_path: Path, caption: str, alt: str, width=6.65):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = True
    shape = p.add_run().add_picture(str(image_path), width=Inches(width))
    add_alt_text(shape, caption, alt)
    add_caption(doc, caption)


def add_screenshot_group(doc: Document, items):
    table = doc.add_table(rows=2, cols=len(items))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_no_borders(table)
    # The first row functions as the visual header for each screenshot column.
    # Mark it explicitly so assistive tools can identify the table structure.
    trPr = table.rows[0]._tr.get_or_add_trPr()
    repeat = OxmlElement("w:tblHeader")
    repeat.set(qn("w:val"), "true")
    trPr.append(repeat)
    for cell in table._cells:
        set_cell_margins(cell, 35, 45, 35, 45)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    for idx, (path, caption) in enumerate(items):
        image_cell = table.cell(0, idx)
        image_p = image_cell.paragraphs[0]
        image_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        shape = image_p.add_run().add_picture(str(path), width=Inches(2.02))
        add_alt_text(shape, caption, f"知衡产品界面：{caption}")
        cap_cell = table.cell(1, idx)
        cap_cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        cap_p = cap_cell.paragraphs[0]
        cap_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap_p.paragraph_format.space_before = Pt(1)
        cap_p.paragraph_format.space_after = Pt(1)
        run = cap_p.add_run(caption)
        set_run_font(run, BODY_FONT, 8.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)


def add_three_line_table(doc: Document, title: str, headers, rows, widths):
    caption = doc.add_paragraph(title)
    caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption.paragraph_format.first_line_indent = Pt(0)
    caption.paragraph_format.space_before = Pt(5)
    caption.paragraph_format.space_after = Pt(3)
    caption.paragraph_format.keep_with_next = True
    for run in caption.runs:
        set_run_font(run, BODY_FONT, 9.2, True)

    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_three_line_borders(table)
    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        cell.width = Inches(widths[idx])
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(cell, 75, 70, 75, 70)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.first_line_indent = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        run = p.add_run(header)
        set_run_font(run, HEADING_FONT, 9.2, True)
        set_cell_bottom_border(cell)
    trPr = table.rows[0]._tr.get_or_add_trPr()
    repeat = OxmlElement("w:tblHeader")
    repeat.set(qn("w:val"), "true")
    trPr.append(repeat)

    for row_data in rows:
        row = table.add_row()
        for idx, value in enumerate(row_data):
            cell = row.cells[idx]
            cell.width = Inches(widths[idx])
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            set_cell_margins(cell, 65, 70, 65, 70)
            p = cell.paragraphs[0]
            p.paragraph_format.first_line_indent = Pt(0)
            p.paragraph_format.space_after = Pt(0)
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER if idx == 0 else WD_ALIGN_PARAGRAPH.LEFT
            run = p.add_run(value)
            set_run_font(run, BODY_FONT, 8.8)
    after = doc.add_paragraph()
    after.paragraph_format.space_after = Pt(0)


def configure_styles(doc: Document):
    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = BODY_FONT
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), BODY_FONT)
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = RGBColor(0, 0, 0)
    normal.paragraph_format.line_spacing = 1.12
    normal.paragraph_format.space_after = Pt(3.5)
    normal.paragraph_format.first_line_indent = Pt(21)
    normal.paragraph_format.widow_control = True

    title = styles["Title"]
    title.font.name = TITLE_FONT
    title._element.rPr.rFonts.set(qn("w:eastAsia"), TITLE_FONT)
    title.font.size = Pt(24)
    title.font.bold = True
    title.font.color.rgb = RGBColor(0, 0, 0)
    title.paragraph_format.space_after = Pt(18)
    title_ppr = title.element.get_or_add_pPr()
    title_border = title_ppr.find(qn("w:pBdr"))
    if title_border is not None:
        title_ppr.remove(title_border)

    h1 = styles["Heading 1"]
    h1.font.name = HEADING_FONT
    h1._element.rPr.rFonts.set(qn("w:eastAsia"), HEADING_FONT)
    h1.font.size = Pt(14.5)
    h1.font.bold = True
    h1.font.color.rgb = RGBColor(0, 0, 0)
    h1.paragraph_format.space_before = Pt(10)
    h1.paragraph_format.space_after = Pt(5)
    h1.paragraph_format.keep_with_next = True
    h1.paragraph_format.page_break_before = False

    h2 = styles["Heading 2"]
    h2.font.name = SUBHEADING_FONT
    h2._element.rPr.rFonts.set(qn("w:eastAsia"), SUBHEADING_FONT)
    h2.font.size = Pt(11.5)
    h2.font.bold = True
    h2.font.color.rgb = RGBColor(0, 0, 0)
    h2.paragraph_format.space_before = Pt(6)
    h2.paragraph_format.space_after = Pt(2)
    h2.paragraph_format.keep_with_next = True
    h2.paragraph_format.page_break_before = False

    caption = styles["Caption"]
    caption.font.name = BODY_FONT
    caption._element.rPr.rFonts.set(qn("w:eastAsia"), BODY_FONT)
    caption.font.size = Pt(8.5)
    caption.font.color.rgb = RGBColor(0, 0, 0)


def add_toc(doc: Document, sections, page_map: dict[str, int] | None):
    heading = doc.add_paragraph("目录", style="Heading 1")
    heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
    heading.paragraph_format.space_before = Pt(0)
    heading.paragraph_format.space_after = Pt(8)
    add_bookmark(heading, "TOC", 1000)
    for idx, section in enumerate(sections):
        p = doc.add_paragraph()
        p.paragraph_format.first_line_indent = Pt(0)
        p.paragraph_format.left_indent = Pt(8)
        p.paragraph_format.right_indent = Pt(8)
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(3)
        tabs = OxmlElement("w:tabs")
        tab = OxmlElement("w:tab")
        tab.set(qn("w:val"), "right")
        tab.set(qn("w:leader"), "dot")
        tab.set(qn("w:pos"), "9900")
        tabs.append(tab)
        p._p.get_or_add_pPr().append(tabs)
        append_internal_hyperlink(p, f"sec{idx + 1:03d}", section["heading"], 10.2)
        page_value = str((page_map or {}).get(section["heading"], 0)).zfill(2)
        page_run = p.add_run("\t" + page_value)
        set_run_font(page_run, BODY_FONT, 10.2)

    note = doc.add_paragraph("目录页码以正文起始页为第1页")
    note.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    note.paragraph_format.first_line_indent = Pt(0)
    note.paragraph_format.space_before = Pt(6)
    note.paragraph_format.space_after = Pt(0)
    for run in note.runs:
        set_run_font(run, BODY_FONT, 8)
    doc.add_page_break()


THREE_LINE_TABLES = {
    2: (
        "表1 主要痛点与产品响应",
        ["痛点", "现有问题", "知衡响应"],
        [
            ["数据难懂", "指标分散，用户自行解释", "AI基于个人事实生成分层说明"],
            ["个体差异", "固定阈值忽略个人基线", "质量守门后与过去的自己比较"],
            ["情境缺失", "客观数据与生活事件割裂", "整合主观感受与生活背景"],
            ["建议泛化", "通用建议缺少执行条件", "一次生成一个低风险微计划"],
            ["无法验证", "建议结束后缺少结果记录", "综合完成率、客观与主观变化评估"],
        ],
        [1.1, 2.65, 2.85],
    ),
    5: (
        "表2 核心功能与输出结果",
        ["功能模块", "核心处理", "面向用户的结果"],
        [
            ["AI健康助手", "理解问题并选择相关事实", "有依据的自然语言解释"],
            ["质量与趋势", "计算覆盖率、基线和变化", "可信趋势与数据不足提示"],
            ["情境记录", "连接感受与生活事件", "更贴近真实生活的解释"],
            ["微计划", "匹配低风险短周期行动", "可确认、暂停和停止的计划"],
            ["效果评估", "比较执行、客观与主观结果", "克制、可追溯的结果说明"],
            ["有效方法", "累计多次独立验证", "个人可复用的方法库"],
        ],
        [1.25, 2.55, 2.8],
    ),
    7: (
        "表3 系统分层与职责",
        ["层级", "主要职责", "关键约束"],
        [
            ["数据接入层", "授权读取并统一映射多源数据", "只获取当前功能所需数据"],
            ["本地数据层", "保存感受、事件、计划关联与快照", "原始样本默认不上传"],
            ["分析决策层", "质量、基线、趋势和结果评估", "固定输入产生固定结果"],
            ["AI服务层", "语义理解、解释与行动组织", "只消费最小化事实包"],
            ["业务闭环层", "连接洞察、计划、执行和方法", "关键动作需用户确认"],
            ["交互展示层", "展示依据、不确定性和控制入口", "低焦虑、非诊断表达"],
        ],
        [1.25, 2.7, 2.65],
    ),
    10: (
        "表4 AI智能体工作阶段",
        ["阶段", "AI任务", "程序与安全约束"],
        [
            ["任务识别", "识别趋势、原因、计划或结果问题", "高风险意图优先分流"],
            ["事实装配", "选择回答所需的个人事实", "白名单字段与最小必要原则"],
            ["解释与行动", "生成分层解释和候选微计划", "数值核对、模板限制、用户确认"],
            ["结果学习", "总结执行结果并更新后续上下文", "不改写历史，不宣称确定因果"],
        ],
        [1.15, 2.65, 2.8],
    ),
    13: (
        "表5 不同产品路径对比",
        ["产品路径", "个人事实", "行动闭环", "结果验证", "安全边界"],
        [
            ["数据展示应用", "较强", "较弱", "较弱", "依赖平台"],
            ["通用AI问答", "较弱", "一般", "较弱", "依赖模型"],
            ["习惯管理工具", "较弱", "较强", "一般", "非健康专用"],
            ["知衡", "较强", "较强", "较强", "程序与AI双重约束"],
        ],
        [1.35, 1.2, 1.2, 1.2, 1.65],
    ),
}


def build(md_path: Path, assets_dir: Path, output_path: Path, page_map: dict[str, int] | None):
    title, sections = parse_markdown(md_path)
    doc = Document()
    configure_styles(doc)

    cover = doc.sections[0]
    cover.page_width = Inches(8.27)
    cover.page_height = Inches(11.69)
    cover.top_margin = Inches(0.75)
    cover.bottom_margin = Inches(0.7)
    cover.left_margin = Inches(0.68)
    cover.right_margin = Inches(0.68)

    for _ in range(5):
        doc.add_paragraph()
    event_p = doc.add_paragraph()
    event_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    event_p.paragraph_format.first_line_indent = Pt(0)
    event_p.paragraph_format.space_after = Pt(20)
    event_run = event_p.add_run("2026年iCAN大学生创新创业大赛AI应用创新挑战赛")
    set_run_font(event_run, HEADING_FONT, 15, True)

    title_p = doc.add_paragraph(style="Title")
    title_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title_p.paragraph_format.first_line_indent = Pt(0)
    title_p.paragraph_format.space_after = Pt(12)
    title_run = title_p.add_run("应用方案")
    set_run_font(title_run, HEADING_FONT, 25, True)

    project_p = doc.add_paragraph()
    project_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    project_p.paragraph_format.first_line_indent = Pt(0)
    project_p.paragraph_format.space_before = Pt(2)
    project_p.paragraph_format.space_after = Pt(0)
    project_run = project_p.add_run("知衡AI健康洞察与行动平台")
    set_run_font(project_run, TITLE_FONT, 16, True)

    body_section = doc.add_section(WD_SECTION_START.NEW_PAGE)
    body_section.page_width = Inches(8.27)
    body_section.page_height = Inches(11.69)
    body_section.top_margin = Inches(0.55)
    body_section.bottom_margin = Inches(0.55)
    body_section.left_margin = Inches(0.64)
    body_section.right_margin = Inches(0.64)
    body_section.header_distance = Inches(0.27)
    body_section.footer_distance = Inches(0.3)
    body_section.header.is_linked_to_previous = False
    body_section.footer.is_linked_to_previous = False
    set_page_number_start(body_section, 1)

    header_p = body_section.header.paragraphs[0]
    header_p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    header_p.paragraph_format.space_after = Pt(0)
    header_run = header_p.add_run("知衡AI健康洞察与行动平台应用方案")
    set_run_font(header_run, HEADING_FONT, 8.5, False)
    footer_p = body_section.footer.paragraphs[0]
    add_page_field(footer_p)

    add_toc(doc, sections, page_map)

    png_dir = assets_dir / "png"
    shots_dir = assets_dir / "产品截图"
    shot_groups = {
        2: [
            (shots_dir / "01-today.png", "图4 今日概览"),
            (shots_dir / "02-insights.png", "图5 洞悉详情"),
            (shots_dir / "03-ai-assistant.png", "图6 AI助手"),
        ],
        5: [
            (shots_dir / "04-micro-plan-active.png", "图7 进行中的微计划"),
            (shots_dir / "05-plan-evaluation.png", "图8 计划评估"),
            (shots_dir / "06-effective-methods.png", "图9 我的有效方法"),
        ],
    }

    for sec_idx, section in enumerate(sections, start=1):
        heading_p = doc.add_paragraph(section["heading"], style="Heading 1")
        add_bookmark(heading_p, f"sec{sec_idx:03d}", sec_idx)
        subheads = SUBHEADS.get(sec_idx, {})
        for p_idx, text in enumerate(section["paragraphs"]):
            if p_idx in subheads:
                doc.add_paragraph(subheads[p_idx], style="Heading 2")
            p = doc.add_paragraph(text)
            p.style = doc.styles["Normal"]
            if sec_idx == 8 and p_idx in shot_groups:
                add_screenshot_group(doc, shot_groups[p_idx])

        if sec_idx in THREE_LINE_TABLES:
            add_three_line_table(doc, *THREE_LINE_TABLES[sec_idx])

        if sec_idx == 1:
            add_wide_figure(
                doc,
                png_dir / "01-ai-health-closed-loop.png",
                "图1 AI健康洞察与行动闭环",
                "健康数据经质量守门、个人基线、AI洞察、微计划和效果评估后沉淀为个人有效方法",
            )
        elif sec_idx == 7:
            add_wide_figure(
                doc,
                png_dir / "02-system-architecture.png",
                "图2 系统技术架构",
                "知衡的数据接入、本地分析、AI服务、业务闭环与交互展示分层架构",
            )
        elif sec_idx == 9:
            add_wide_figure(
                doc,
                png_dir / "03-user-journey.png",
                "图3 用户操作流程",
                "用户从授权数据、查看洞察、与AI交互到执行微计划和沉淀有效方法的操作流程",
            )

    core = doc.core_properties
    core.title = title
    core.subject = "AI健康洞察与行动平台应用方案"
    core.author = "知衡项目组"
    core.keywords = "AI健康, 个人基线, 微计划, 健康洞察"
    core.comments = ""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(output_path)
    print(json.dumps({"output": str(output_path), "sections": len(sections)}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--md", type=Path, required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--page-map", type=Path)
    args = parser.parse_args()
    page_map = None
    if args.page_map:
        page_map = json.loads(args.page_map.read_text(encoding="utf-8"))
    build(args.md, args.assets, args.out, page_map)


if __name__ == "__main__":
    main()
