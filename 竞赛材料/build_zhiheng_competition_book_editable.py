from __future__ import annotations

import math
import sys
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
from docx import Document
from docx.enum.section import WD_SECTION_START
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_ROW_HEIGHT_RULE
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor, Twips


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent
OUTPUT = PROJECT_ROOT / "output" / "word" / "知衡——从健康洞察到行为改变的AI个人健康智能体_国创赛项目计划书.docx"
ASSET_DIR = ROOT / "assets" / "editable-book"
SCREEN_DIR = ROOT / "assets"
LOGO = PROJECT_ROOT / "Design" / "AppIcon-Zhiheng-v3-focus-liquid-glass.png"
FONT_FILE = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_NAME = "Heiti SC"

SKILL_ROOT = Path("/Users/chenweiyang/.codex/plugins/cache/openai-primary-runtime/documents/26.826.12353/skills/documents")
sys.path.insert(0, str(SKILL_ROOT / "scripts"))
from table_geometry import apply_table_geometry, column_widths_from_weights, section_content_width_dxa


# narrative_proposal preset with named overrides:
# - competition_a4: A4 portrait, 2.0 cm side margins, 1.85 cm top/bottom.
# - monochrome: all hierarchy in black/gray; no decorative color.
INK = "111111"
MUTED = "666666"
LIGHT = "F2F2F2"
LIGHTER = "F8F8F8"
LINE = "3F3F3F"
WHITE = "FFFFFF"

def set_run_font(run, size: float | None = None, bold: bool | None = None,
                 color: str = INK, italic: bool | None = None):
    run.font.name = FONT_NAME
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), FONT_NAME)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), FONT_NAME)
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), FONT_NAME)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic
    run.font.color.rgb = RGBColor.from_string(color)


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    header = OxmlElement("w:tblHeader")
    header.set(qn("w:val"), "true")
    tr_pr.append(header)


def set_cell_shading(cell, fill: str):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)
    shd.set(qn("w:val"), "clear")


def set_cell_borders(cell, **edges):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_borders = tc_pr.first_child_found_in("w:tcBorders")
    if tc_borders is None:
        tc_borders = OxmlElement("w:tcBorders")
        tc_pr.append(tc_borders)
    for edge_name, edge_data in edges.items():
        tag = f"w:{edge_name}"
        edge = tc_borders.find(qn(tag))
        if edge is None:
            edge = OxmlElement(tag)
            tc_borders.append(edge)
        for key, value in edge_data.items():
            edge.set(qn(f"w:{key}"), str(value))


def set_table_borders_none(table):
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge_name in ("top", "left", "bottom", "right", "insideH", "insideV"):
        edge = borders.find(qn(f"w:{edge_name}"))
        if edge is None:
            edge = OxmlElement(f"w:{edge_name}")
            borders.append(edge)
        edge.set(qn("w:val"), "nil")


def add_page_field(paragraph):
    run = paragraph.add_run()
    fld_char = OxmlElement("w:fldChar")
    fld_char.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    sep = OxmlElement("w:fldChar")
    sep.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = "1"
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend([fld_char, instr, sep, text, end])
    set_run_font(run, 8.5, color=MUTED)


def add_hyperlink(paragraph, text: str, url: str):
    part = paragraph.part
    rel_id = part.relate_to(url, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", is_external=True)
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), rel_id)
    run = OxmlElement("w:r")
    r_pr = OxmlElement("w:rPr")
    r_fonts = OxmlElement("w:rFonts")
    r_fonts.set(qn("w:ascii"), FONT_NAME)
    r_fonts.set(qn("w:hAnsi"), FONT_NAME)
    r_fonts.set(qn("w:eastAsia"), FONT_NAME)
    color = OxmlElement("w:color")
    color.set(qn("w:val"), "333333")
    underline = OxmlElement("w:u")
    underline.set(qn("w:val"), "single")
    r_pr.extend([r_fonts, color, underline])
    run.append(r_pr)
    value = OxmlElement("w:t")
    value.text = text
    run.append(value)
    hyperlink.append(run)
    paragraph._p.append(hyperlink)


def paragraph_border_and_shading(paragraph, fill=LIGHT, left=True):
    p_pr = paragraph._p.get_or_add_pPr()
    shd = p_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        p_pr.append(shd)
    shd.set(qn("w:fill"), fill)
    shd.set(qn("w:val"), "clear")
    if left:
        p_bdr = p_pr.find(qn("w:pBdr"))
        if p_bdr is None:
            p_bdr = OxmlElement("w:pBdr")
            p_pr.append(p_bdr)
        edge = OxmlElement("w:left")
        edge.set(qn("w:val"), "single")
        edge.set(qn("w:sz"), "18")
        edge.set(qn("w:space"), "7")
        edge.set(qn("w:color"), LINE)
        p_bdr.append(edge)


def set_alt_text(inline_shape, title: str, description: str):
    doc_pr = inline_shape._inline.docPr
    doc_pr.set("title", title)
    doc_pr.set("descr", description)


def configure_styles(doc: Document):
    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = FONT_NAME
    normal._element.rPr.rFonts.set(qn("w:ascii"), FONT_NAME)
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), FONT_NAME)
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    normal.font.size = Pt(10.2)
    normal.font.color.rgb = RGBColor.from_string(INK)
    pf = normal.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf.space_before = Pt(0)
    pf.space_after = Pt(6)
    pf.line_spacing = 1.28

    title = styles["Title"]
    title.font.name = FONT_NAME
    title._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    title.font.size = Pt(28)
    title.font.bold = True
    title.font.color.rgb = RGBColor.from_string(INK)
    title.paragraph_format.space_after = Pt(8)

    subtitle = styles["Subtitle"]
    subtitle.font.name = FONT_NAME
    subtitle._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    subtitle.font.size = Pt(14)
    subtitle.font.color.rgb = RGBColor.from_string(MUTED)
    subtitle.paragraph_format.space_after = Pt(12)

    for style_name, size, before, after in (
        ("Heading 1", 17.5, 0, 8),
        ("Heading 2", 13.0, 10, 5),
        ("Heading 3", 11.2, 7, 3),
    ):
        style = styles[style_name]
        style.font.name = FONT_NAME
        style._element.rPr.rFonts.set(qn("w:ascii"), FONT_NAME)
        style._element.rPr.rFonts.set(qn("w:hAnsi"), FONT_NAME)
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor.from_string(INK)
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True

    caption = styles["Caption"]
    caption.font.name = FONT_NAME
    caption._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    caption.font.size = Pt(8.3)
    caption.font.italic = False
    caption.font.color.rgb = RGBColor.from_string(MUTED)
    caption.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption.paragraph_format.space_before = Pt(3)
    caption.paragraph_format.space_after = Pt(6)
    caption.paragraph_format.keep_with_next = True

    if "Source" not in [s.name for s in styles]:
        styles.add_style("Source", WD_STYLE_TYPE.PARAGRAPH)
    source = styles["Source"]
    source.font.name = FONT_NAME
    source._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    source.font.size = Pt(7.7)
    source.font.color.rgb = RGBColor.from_string(MUTED)
    source.paragraph_format.space_before = Pt(4)
    source.paragraph_format.space_after = Pt(4)
    source.paragraph_format.line_spacing = 1.15

    if "Lead" not in [s.name for s in styles]:
        styles.add_style("Lead", WD_STYLE_TYPE.PARAGRAPH)
    lead = styles["Lead"]
    lead.font.name = FONT_NAME
    lead._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    lead.font.size = Pt(12.2)
    lead.font.bold = True
    lead.font.color.rgb = RGBColor.from_string(INK)
    lead.paragraph_format.space_after = Pt(9)
    lead.paragraph_format.line_spacing = 1.25

    if "Callout" not in [s.name for s in styles]:
        styles.add_style("Callout", WD_STYLE_TYPE.PARAGRAPH)
    callout = styles["Callout"]
    callout.font.name = FONT_NAME
    callout._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    callout.font.size = Pt(9.5)
    callout.paragraph_format.left_indent = Cm(0.28)
    callout.paragraph_format.right_indent = Cm(0.18)
    callout.paragraph_format.space_before = Pt(5)
    callout.paragraph_format.space_after = Pt(7)
    callout.paragraph_format.line_spacing = 1.2


def configure_page(doc: Document):
    section = doc.sections[0]
    section.page_width = Cm(21)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(2.0)
    section.right_margin = Cm(2.0)
    section.top_margin = Cm(1.85)
    section.bottom_margin = Cm(1.85)
    section.header_distance = Cm(0.75)
    section.footer_distance = Cm(0.75)
    section.different_first_page_header_footer = True

    header = section.header
    p = header.paragraphs[0]
    p.clear()
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.tab_stops.add_tab_stop(Cm(17), alignment=2)
    r = p.add_run("知衡｜国创赛项目计划书")
    set_run_font(r, 8.2, bold=True, color=MUTED)
    r = p.add_run("\t西南科技大学")
    set_run_font(r, 8.2, color=MUTED)
    p_pr = p._p.get_or_add_pPr()
    p_bdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), "4")
    bottom.set(qn("w:space"), "4")
    bottom.set(qn("w:color"), "B5B5B5")
    p_bdr.append(bottom)
    p_pr.append(p_bdr)

    footer = section.footer
    p = footer.paragraphs[0]
    p.clear()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(0)
    r = p.add_run("健康管理与生活方式改善工具　·　")
    set_run_font(r, 7.8, color=MUTED)
    add_page_field(p)
    r = p.add_run("　·　非疾病诊断、治疗或持续急救监护软件")
    set_run_font(r, 7.8, color=MUTED)


def add_page_title(doc: Document, number: str, title: str, lead: str | None = None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(number)
    set_run_font(r, 8.8, bold=True, color=MUTED)
    h = doc.add_paragraph(title, style="Heading 1")
    h.paragraph_format.keep_with_next = True
    if lead:
        lead_p = doc.add_paragraph(lead, style="Lead")
        lead_p.paragraph_format.keep_with_next = True


PAGE_BLOCK_COUNTER = 0


def end_page(doc: Document):
    """Keep front matter on dedicated pages, then pair related sections densely."""
    global PAGE_BLOCK_COUNTER
    PAGE_BLOCK_COUNTER += 1
    if PAGE_BLOCK_COUNTER <= 5:
        doc.add_page_break()
    else:
        spacer = doc.add_paragraph()
        spacer.paragraph_format.space_before = Pt(5)
        spacer.paragraph_format.space_after = Pt(5)


def add_body(doc: Document, text: str, bold_lead: str | None = None):
    p = doc.add_paragraph()
    if bold_lead:
        r = p.add_run(bold_lead)
        set_run_font(r, 10.2, bold=True)
    r = p.add_run(text)
    set_run_font(r, 10.2)
    return p


def add_label_paragraph(doc: Document, label: str, text: str):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(5)
    r = p.add_run(label + "　")
    set_run_font(r, 10.0, bold=True)
    r = p.add_run(text)
    set_run_font(r, 10.0)
    return p


def add_callout(doc: Document, title: str, text: str):
    p = doc.add_paragraph(style="Callout")
    r = p.add_run(title + "　")
    set_run_font(r, 9.5, bold=True)
    r = p.add_run(text)
    set_run_font(r, 9.5)
    paragraph_border_and_shading(p)
    return p


def add_source(doc: Document, text: str, url: str | None = None):
    p = doc.add_paragraph(style="Source")
    r = p.add_run("资料来源：" + text)
    set_run_font(r, 7.7, color=MUTED)
    if url:
        p.add_run("　")
        add_hyperlink(p, "查看原文", url)
    return p


def add_figure(doc: Document, path: Path, width_cm: float, caption: str, alt: str,
               source: str | None = None, source_url: str | None = None):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(0)
    shape = p.add_run().add_picture(str(path), width=Cm(width_cm))
    set_alt_text(shape, caption, alt)
    c = doc.add_paragraph(caption, style="Caption")
    c.paragraph_format.keep_with_next = bool(source)
    if source:
        add_source(doc, source, source_url)


def three_line_table(doc: Document, headers: list[str], rows: list[list[str]],
                     weights: list[float], font_size: float = 8.6,
                     alignments: list[int] | None = None):
    table = doc.add_table(rows=1, cols=len(headers))
    set_table_borders_none(table)
    table.autofit = False
    header = table.rows[0]
    set_repeat_table_header(header)
    for i, text in enumerate(headers):
        cell = header.cells[i]
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.15
        r = p.add_run(text)
        set_run_font(r, font_size, bold=True)
    for row_data in rows:
        row = table.add_row()
        row.height_rule = WD_ROW_HEIGHT_RULE.AUTO
        for i, text in enumerate(row_data):
            cell = row.cells[i]
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            if alignments:
                p.alignment = alignments[i]
            else:
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT if len(text) > 16 else WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing = 1.18
            r = p.add_run(text)
            set_run_font(r, font_size)

    width_dxa = section_content_width_dxa(doc.sections[0])
    widths = column_widths_from_weights(weights, total_width_dxa=width_dxa)
    apply_table_geometry(
        table, widths, table_width_dxa=width_dxa, indent_dxa=100,
        cell_margins_dxa={"top": 78, "bottom": 78, "start": 100, "end": 100}
    )

    nil = {"val": "nil"}
    top = {"val": "single", "sz": "12", "color": LINE, "space": "0"}
    middle = {"val": "single", "sz": "6", "color": LINE, "space": "0"}
    bottom = {"val": "single", "sz": "12", "color": LINE, "space": "0"}
    for cell in table.rows[0].cells:
        set_cell_borders(cell, top=top, bottom=middle, left=nil, right=nil, insideH=nil, insideV=nil)
    for row in table.rows[1:-1]:
        for cell in row.cells:
            set_cell_borders(cell, top=nil, bottom=nil, left=nil, right=nil, insideH=nil, insideV=nil)
    if len(table.rows) > 1:
        for cell in table.rows[-1].cells:
            set_cell_borders(cell, top=nil, bottom=bottom, left=nil, right=nil, insideH=nil, insideV=nil)
    table.rows[0]._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
    for row in table.rows[1:]:
        row._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
    doc.add_paragraph().paragraph_format.space_after = Pt(0)
    return table


def grayscale_image(src: Path, dst: Path):
    image = Image.open(src).convert("L")
    image = ImageOps.autocontrast(image)
    image.save(dst, quality=95)


def image_font(size: int):
    return ImageFont.truetype(FONT_FILE, size=size)


def canvas(name: str, size=(1800, 820)):
    path = ASSET_DIR / name
    return Image.new("RGB", size, "white"), path


def centered(draw, xy, text, font, fill="#111111", anchor="mm", spacing=8):
    draw.multiline_text(xy, text, font=font, fill=fill, anchor=anchor,
                        align="center", spacing=spacing)


def save_canvas(image, path):
    image.save(path, quality=95, dpi=(220, 220))
    return path


def arrow(draw, start, end, fill="#333333", width=5):
    draw.line([start, end], fill=fill, width=width)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    wing = 18
    for delta in (2.55, -2.55):
        point = (end[0] + wing * math.cos(angle + delta),
                 end[1] + wing * math.sin(angle + delta))
        draw.line([end, point], fill=fill, width=width)


def generate_assets():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    grayscale_image(LOGO, ASSET_DIR / "logo-gray.png")
    for stem in ("zhiheng-home", "zhiheng-insights", "zhiheng-plan", "zhiheng-ai"):
        grayscale_image(SCREEN_DIR / f"{stem}.png", ASSET_DIR / f"{stem}-gray.png")

    image, path = canvas("score-map.png")
    draw = ImageDraw.Draw(image)
    centered(draw, (900, 66), "中国国际大学生创新大赛（2026）高教主赛道创意组评分结构", image_font(46))
    names = ["个人成长", "项目创新", "产业价值", "团队协作"]
    values = [30, 30, 25, 15]
    colors = ["#1a1a1a", "#444444", "#777777", "#aaaaaa"]
    for i, (name, value, color) in enumerate(zip(names, values, colors)):
        y = 160 + i * 145
        draw.text((70, y + 34), name, font=image_font(34), fill="#111111")
        draw.rounded_rectangle((300, y, 300 + value * 38, y + 88), radius=15, fill=color)
        draw.text((320 + value * 38, y + 26), f"{value}分", font=image_font(32), fill="#111111")
    score = save_canvas(image, path)

    image, path = canvas("wearable-market.png")
    draw = ImageDraw.Draw(image)
    centered(draw, (900, 66), "2025年中国腕戴设备市场出货量", image_font(46))
    labels = ["智能手表", "手环", "腕戴设备合计"]
    values = [5061, 2329, 7390]
    colors = ["#4a4a4a", "#999999", "#161616"]
    baseline, max_height = 700, 500
    draw.line((150, baseline, 1690, baseline), fill="#333333", width=4)
    for i, (label, value, color) in enumerate(zip(labels, values, colors)):
        x = 250 + i * 520
        height = int(value / 8000 * max_height)
        draw.rounded_rectangle((x, baseline - height, x + 260, baseline), radius=12, fill=color)
        centered(draw, (x + 130, baseline - height - 35), f"{value:,}万台", image_font(32))
        centered(draw, (x + 130, baseline + 55), label, image_font(32))
    market = save_canvas(image, path)

    image, path = canvas("research-evidence.png")
    draw = ImageDraw.Draw(image)
    evidence = [
        ("31%", "全球成年人未达到推荐身体活动水平\nWHO，2022年数据"),
        ("51%", "56名mHealth用户中使用多个健康应用\nIEEE Access用户调查"),
        ("9%", "164项数字健康技术中评估\n“可理解性/可行动性”的比例"),
    ]
    for i, (value, label) in enumerate(evidence):
        x = 45 + i * 585
        draw.rounded_rectangle((x, 80, x + 535, 730), radius=35, fill="#f5f5f5", outline="#333333", width=4)
        centered(draw, (x + 267, 305), value, image_font(88))
        centered(draw, (x + 267, 530), label, image_font(28), spacing=18)
    research = save_canvas(image, path)

    image, path = canvas("closed-loop.png", (2100, 700))
    draw = ImageDraw.Draw(image)
    nodes = ["健康数据", "质量判断", "个人基线", "主客观洞察", "3—7天微计划", "效果评估", "方法资产"]
    for i, node in enumerate(nodes):
        x = 30 + i * 295
        draw.rounded_rectangle((x, 220, x + 245, 470), radius=28,
                               fill="#f4f4f4" if i % 2 else "#dedede", outline="#333333", width=4)
        centered(draw, (x + 122, 345), node, image_font(29))
        if i < len(nodes) - 1:
            arrow(draw, (x + 250, 345), (x + 285, 345), width=4)
    closed_loop = save_canvas(image, path)

    image, path = canvas("architecture.png", (1800, 980))
    draw = ImageDraw.Draw(image)
    layers = [
        ("产品与交互层", "SwiftUI五标签页面｜演示/真实数据状态｜可访问性"),
        ("应用服务层", "HealthDataService｜CarePlanService｜AIService｜用例编排"),
        ("领域与分析层", "数据质量｜个人基线｜趋势｜事实包｜计划评估"),
        ("基础设施层", "HealthKit｜CareKitStore｜SwiftData｜URLSession/Keychain"),
    ]
    colors = ["#e5e5e5", "#d1d1d1", "#bcbcbc", "#a8a8a8"]
    for i, ((name, detail), color) in enumerate(zip(layers, colors)):
        y = 75 + i * 220
        draw.rounded_rectangle((90, y, 1710, y + 165), radius=28, fill=color, outline="#333333", width=4)
        draw.text((150, y + 55), name, font=image_font(38), fill="#111111")
        draw.text((560, y + 59), detail, font=image_font(30), fill="#111111")
    architecture = save_canvas(image, path)

    image, path = canvas("ai-boundary.png", (1800, 920))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((70, 105, 930, 815), radius=35, fill="#f2f2f2", outline="#222222", width=5)
    draw.rounded_rectangle((1170, 205, 1730, 715), radius=35, fill="#dddddd", outline="#222222", width=5)
    centered(draw, (500, 195), "设备本地", image_font(44))
    centered(draw, (500, 375), "HealthKit聚合 → 质量判断 → 基线/趋势", image_font(30))
    centered(draw, (500, 510), "形成最小化结构化健康事实包", image_font(30))
    centered(draw, (500, 650), "诊断/用药/紧急场景先由独立规则处理", image_font(28))
    centered(draw, (1450, 300), "AI服务", image_font(44))
    centered(draw, (1450, 500), "解释事实\n表达不确定性\n建议白名单行动", image_font(31), spacing=18)
    arrow(draw, (940, 460), (1150, 460), width=5)
    centered(draw, (1045, 405), "仅发送聚合事实", image_font(26))
    ai_flow = save_canvas(image, path)

    image, path = canvas("roadmap.png", (2000, 820))
    draw = ImageDraw.Draw(image)
    stages = [
        ("2026.07—08", "工程与数据闭环", "已完成核心页面、健康数据、AI与微计划基础"),
        ("2026.09", "历史一致性与材料", "完成S10-12，冻结比赛演示版本"),
        ("2026.09—10", "一手用户验证", "访谈、问卷、可用性与5—7天日记研究"),
        ("2026.10—11", "迭代与答辩", "修复理解问题，补齐证据、PPT与路演"),
    ]
    draw.line((140, 340, 1860, 340), fill="#222222", width=6)
    for i, (time, name, detail) in enumerate(stages):
        x = 170 + i * 550
        draw.ellipse((x - 18, 322, x + 18, 358), fill="#222222")
        centered(draw, (x, 190), time, image_font(30))
        centered(draw, (x, 430), name, image_font(32))
        centered(draw, (x, 595), "\n".join(textwrap.wrap(detail, 13)), image_font(24), spacing=12)
    roadmap = save_canvas(image, path)

    image, path = canvas("engineering-evidence.png")
    draw = ImageDraw.Draw(image)
    metrics = [("162", "iOS自动化测试"), ("14", "AI代理测试"), ("10", "低风险微计划模板"), ("16", "健康指标聚合映射")]
    for i, (value, label) in enumerate(metrics):
        x = 35 + i * 440
        draw.rounded_rectangle((x, 120, x + 400, 700), radius=35, fill="#f3f3f3", outline="#333333", width=4)
        centered(draw, (x + 200, 335), value, image_font(88))
        centered(draw, (x + 200, 525), label, image_font(29))
    evidence = save_canvas(image, path)

    return {
        "score": score, "market": market, "research": research, "closed_loop": closed_loop,
        "architecture": architecture, "ai_flow": ai_flow, "roadmap": roadmap, "evidence": evidence,
    }


def add_phone_pair(doc: Document, left: Path, right: Path, left_caption: str, right_caption: str):
    pair_path = ASSET_DIR / f"pair-{left.stem}-{right.stem}.png"
    pair = Image.new("RGB", (1600, 1780), "white")
    for index, path in enumerate((left, right)):
        phone = Image.open(path).convert("L").convert("RGB")
        phone.thumbnail((690, 1600))
        x = 80 + index * 760 + (690 - phone.width) // 2
        y = 25 + (1600 - phone.height) // 2
        pair.paste(phone, (x, y))
    draw = ImageDraw.Draw(pair)
    draw.line((70, 1650, 1530, 1650), fill="#666666", width=3)
    centered(draw, (400, 1710), left_caption.split("：", 1)[0], image_font(25), fill="#555555")
    centered(draw, (1200, 1710), right_caption.split("：", 1)[0], image_font(25), fill="#555555")
    pair.save(pair_path, quality=95, dpi=(220, 220))

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shape = p.add_run().add_picture(str(pair_path), width=Cm(11.7))
    set_alt_text(shape, "知衡产品双页面展示", f"{left_caption}；{right_caption}")
    cp = doc.add_paragraph(style="Caption")
    cp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = cp.add_run(left_caption + "　　" + right_caption)
    set_run_font(r, 8.1, color=MUTED)


def build_document():
    global PAGE_BLOCK_COUNTER
    PAGE_BLOCK_COUNTER = 0
    assets = generate_assets()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = Document()
    configure_styles(doc)
    configure_page(doc)

    # 1 Cover — proposal_centerpiece header pattern, monochrome override.
    doc.add_paragraph().paragraph_format.space_after = Pt(24)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shape = p.add_run().add_picture(str(ASSET_DIR / "logo-gray.png"), width=Cm(3.1))
    set_alt_text(shape, "知衡应用图标", "知衡应用图标的黑白版本，两枚相向的弧形元素象征洞察与行动之间的连接。")
    p = doc.add_paragraph("中国国际大学生创新大赛（2026）", style="Subtitle")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(18)
    p = doc.add_paragraph("知衡", style="Title")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(4)
    p = doc.add_paragraph("从健康洞察到行为改变的AI个人健康智能体", style="Subtitle")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(24)
    p = doc.add_paragraph("把健康数据转化为可理解、可执行、可验证的个人健康方案")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.runs[0]
    set_run_font(r, 11.5, bold=True)
    doc.add_paragraph().paragraph_format.space_after = Pt(14)
    three_line_table(doc, ["项目字段", "内容"], [
        ["项目名称", "知衡——从健康洞察到行为改变的AI个人健康智能体"],
        ["参赛学校", "西南科技大学"],
        ["项目负责人", "陈维阳"],
        ["团队成员", "李思磊、杜浩天、陈风博弈、张潼心、王奥"],
        ["拟报组别", "高教主赛道·创意组（最终以学校审核为准）"],
        ["版本日期", "V3.0｜2026年9月"],
    ], [2.8, 7.2], 9.0, [WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT])
    p = doc.add_paragraph("健康管理与生活方式改善工具｜不提供疾病诊断、治疗、处方或持续急救监护")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run_font(p.runs[0], 8.2, color=MUTED)
    end_page(doc)

    # 2
    add_page_title(doc, "项目信息", "版本说明与真实性边界", "本计划书以项目现有工程事实、公开可核验资料和团队明确提供的信息为依据。")
    add_body(doc, "本版为重新制作的原生可编辑Word版本。正文、标题、三线表、图注、页眉页脚和参考文献均为真实Word元素；产品图片为知衡演示模式截图，不包含真实个人健康数据。")
    three_line_table(doc, ["信息类别", "本版写法", "提交前要求"], [
        ["工程成果", "只写入已经完成并有测试记录的功能", "如后续状态变化，按最新日志更新"],
        ["用户调研", "公开研究写为二手研究；团队一手访谈/问卷写为拟开展", "不得虚构人数、比例、原话或满意度"],
        ["市场与竞品", "采用官方或同行评议来源，明确访问日期", "功能变化时重新核验"],
        ["财务、合作、知识产权", "不把未提供材料写成既有事实", "有证明再写入，没有则保持待核验"],
        ["医疗效果", "只描述健康管理、行为支持与工程验证", "不得写成临床有效性或诊疗结论"],
    ], [2.4, 4.6, 3.0], 8.6)
    add_callout(doc, "真实性是必要条件", "2026年评审规则明确要求科技成果、知识产权、财务状况、运营和荣誉材料真实、准确、有效；弄虚作假、抄袭剽窃实行一票否决。本计划书因此主动区分“已完成”“公开证据”“拟验证”。")
    three_line_table(doc, ["项目状态", "可核验依据", "本计划书处理"], [
        ["可运行原型", "iPhone工程、模拟器交互、Debug/Release构建与开发日志", "作为研发基础写入，不等同于规模化产品"],
        ["健康数据能力", "HealthKit授权、16类映射、真实/演示Provider和来源规则", "说明工程边界，不声称覆盖全部设备"],
        ["行动闭环", "10类计划模板、CareKitStore、反馈与结束评估", "说明已实现流程，不声称产生临床效果"],
        ["AI能力", "结构化事实包、SSE流式回答、安全测试和本地降级", "说明受控解释能力，不包装为医生替代品"],
        ["市场与用户", "公开资料调研已完成；团队一手调研尚待开展", "公开证据与拟验证计划分栏呈现"],
    ], [2.1, 4.6, 3.3], 7.6)
    add_body(doc, "计划书采用“事实—判断—行动”三层写法：事实给出来源或工程记录；判断说明适用范围与限制；行动写明下一步如何验证。对于成员分工、指导教师、财务、知识产权和合作等团队尚未提供证明的信息，保留待核验状态，不以合理推测替代真实材料。")
    add_source(doc, "中国国际大学生创新大赛（2026）评审规则，高教主赛道创意组必要条件。", "https://ieeac2015-download.oss-cn-beijing.aliyuncs.com/othersfile/%E4%B8%AD%E5%9B%BD%E5%9B%BD%E9%99%85%E5%A4%A7%E5%AD%A6%E7%94%9F%E5%88%9B%E6%96%B0%E5%A4%A7%E8%B5%9B%EF%BC%882026%EF%BC%89%E8%AF%84%E5%AE%A1%E8%A7%84%E5%88%99.pdf")
    end_page(doc)

    # 3
    add_page_title(doc, "01", "项目摘要", "知衡面向成年用户，解决“数据越来越多，但仍然看不懂、用不好、坚持不下去”的关键断点。")
    add_body(doc, "知衡通过AI健康洞察引擎、个人基线建模、趋势识别和健康行为改善能力，将运动、睡眠、心率等多维健康数据，以及用户的精力、压力、身体感受和生活情境，转化为可理解、可执行、可验证的个体化健康方案。")
    add_body(doc, "知衡不只是记录数据，而是建立“数据质量判断—个人基线—趋势识别—主客观对照—低风险微计划—效果评估—个人方法资产”的闭环。系统优先比较用户与过去的自己，以长期趋势而非单日波动判断状态；证据不足时诚实降级，不以确定疾病措辞制造焦虑。")
    add_figure(doc, assets["closed_loop"], 16.3, "图1　知衡从健康洞察到行为改变的核心闭环", "七个连续步骤：健康数据、质量判断、个人基线、主客观洞察、三至七天微计划、效果评估和方法资产。")
    three_line_table(doc, ["用户问题", "知衡的回答"], [
        ["我最近为什么状态不好？", "在数据质量门槛内，展示相对个人基线的变化，并结合感受与生活情境解释。"],
        ["我现在可以做什么？", "一次只推荐一个3—7天、低风险、可随时停止的微计划。"],
        ["这个方法适合我吗？", "结合完成率、主观反馈、客观趋势和数据质量形成审慎评估。"],
    ], [3.4, 6.6], 8.8)
    three_line_table(doc, ["项目维度", "当前方案摘要"], [
        ["产品形态", "iPhone AI健康洞察与行动助手，读取用户授权的Apple Health数据"],
        ["核心对象", "成年用户，优先大学生、青年职场人、久坐高压力、运动入门和睡眠困扰人群"],
        ["关键技术", "HealthKit＋确定性分析＋SwiftData＋CareKitStore＋受控AI事实包"],
        ["价值闭环", "看懂变化—理解情境—尝试一个小行动—评估结果—沉淀个人方法"],
        ["安全边界", "非诊疗、本地优先、原始样本默认不上传、紧急场景独立规则优先"],
        ["近期目标", "完成历史一致性、真实一手调研、比赛演示版本冻结和证据材料对齐"],
    ], [2.2, 7.8], 8.0)
    end_page(doc)

    # 4-5 TOC
    toc_entries = [
        ("01", "项目摘要"), ("02", "评审规则对标"), ("03", "行业背景与机会"),
        ("04", "用户问题与公开证据"), ("05", "目标用户与场景"), ("06", "用户调研设计"),
        ("07", "用户旅程"), ("08", "产品方案与闭环"), ("09", "产品展示"),
        ("10", "功能体系"), ("11", "数据质量与个人基线"), ("12", "趋势与AI洞察"),
        ("13", "技术架构"), ("14", "AI安全与隐私"), ("15", "微计划与行动验证"),
        ("16", "核心竞争力"), ("17", "系统性创新"), ("18", "竞品与竞争策略"),
        ("19", "市场机会"), ("20", "市场进入路径"), ("21", "商业模式"),
        ("22", "研发与工程证据"), ("23", "用户验证计划"), ("24", "实施路线图"),
        ("25", "团队与协作"), ("26", "社会价值与伦理"), ("27", "风险、知识产权与合规"),
        ("28", "评分证据与待补材料"), ("29", "结语"), ("附录A", "参考资料"),
        ("附录B", "用户问卷与访谈提纲"), ("附录C", "最终提交核验清单"),
    ]
    add_page_title(doc, "目录", "Contents（上）")
    three_line_table(doc, ["章节", "主题"], [[a, b] for a, b in toc_entries[:16]], [1.8, 8.2], 9.0,
                     [WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT])
    add_body(doc, "上半部分回答三个问题：为什么值得做——行业增长与理解行动缺口；为谁做——目标用户、场景和真实调研设计；怎样做——从数据质量、个人基线到产品闭环与页面展示。各章节既给出项目主张，也给出能够核验主张的公开资料或工程证据。")
    add_callout(doc, "评委阅读线索", "不要把知衡理解为单纯的数据展示或聊天应用。前16章形成一条连续证据链：用户问题 → 公开证据 → 用户场景 → 产品闭环 → 数据与AI边界 → 微计划执行。")
    end_page(doc)
    add_page_title(doc, "目录", "Contents（下）")
    three_line_table(doc, ["章节", "主题"], [[a, b] for a, b in toc_entries[16:]], [1.8, 8.2], 9.0,
                     [WD_ALIGN_PARAGRAPH.CENTER, WD_ALIGN_PARAGRAPH.LEFT])
    add_callout(doc, "阅读建议", "网评阶段可优先阅读项目摘要、评审规则对标、产品与创新、研发与工程证据，以及评分证据与待补材料五部分。目录不写死页码，避免后续学校模板调整导致页码失真。")
    three_line_table(doc, ["证据类型", "主要分布", "作用"], [
        ["公开证据", "行业、用户问题、竞品与市场章节", "证明问题方向和市场信号，但不替代本团队一手调研"],
        ["工程证据", "产品、架构、安全、微计划和研发章节", "证明原型真实可运行、数据职责和安全边界可验证"],
        ["待补证据", "用户验证、团队、商业和评分证据章节", "明确终稿前必须真实补齐的研究、贡献和市场材料"],
    ], [2.0, 3.5, 4.5], 7.8)
    end_page(doc)

    # 6
    add_page_title(doc, "02", "2026评审规则对标", "按照高教主赛道创意组“个人成长30、项目创新30、产业价值25、团队协作15”的评分结构组织材料。")
    add_figure(doc, assets["score"], 15.6, "图2　2026高教主赛道创意组评分结构", "横向条形图：个人成长30分、项目创新30分、产业价值25分、团队协作15分。",
               "中国国际大学生创新大赛（2026）评审规则。", "https://ieeac2015-download.oss-cn-beijing.aliyuncs.com/othersfile/%E4%B8%AD%E5%9B%BD%E5%9B%BD%E9%99%85%E5%A4%A7%E5%AD%A6%E7%94%9F%E5%88%9B%E6%96%B0%E5%A4%A7%E8%B5%9B%EF%BC%882026%EF%BC%89%E8%AF%84%E5%AE%A1%E8%A7%84%E5%88%99.pdf")
    three_line_table(doc, ["评审维度", "本计划书对应证据"], [
        ["个人成长（30）", "调研方法、工程迭代、问题解决过程、团队实质贡献和人才培养逻辑。"],
        ["项目创新（30）", "数据质量守门、个人基线、主客观融合、事实受控AI、微计划验证闭环。"],
        ["产业价值（25）", "腕戴设备市场、目标用户、竞品格局、市场进入路径与可持续模式。"],
        ["团队协作（15）", "团队名单、职责框架、协作机制与后续证明材料要求。"],
    ], [3.0, 7.0], 8.7)
    three_line_table(doc, ["答辩主张", "证明材料", "避免的误区"], [
        ["项目来自真实学习与工程实践", "阶段任务、开发日志、测试记录、设计迭代和逐人贡献表", "只展示最终页面，不讲遇到的问题与成长"],
        ["创新是系统闭环而非单一算法", "质量守门、基线、主客观融合、事实包、计划评估的连接关系", "把行业已有的个体基线包装成独占创新"],
        ["产业路径从可触达场景开始", "校园种子用户、任务验证、短期日记研究、真实转化漏斗", "用全国人口或出货量直接估算收入"],
        ["团队协作具有实质产出", "成员任务、代码/文档/研究记录、验证证据和时间投入", "仅列成员姓名或泛化岗位名称"],
    ], [2.7, 4.7, 2.6], 7.4)
    add_callout(doc, "叙事顺序", "先证明问题真实，再证明方案独特且可运行，随后展示验证路径和团队能力；所有成果按“已经完成、正在完成、计划开展”标记成熟度。")
    end_page(doc)

    # 7
    add_page_title(doc, "03", "行业背景：设备普及不等于行为改变", "可穿戴硬件正在增长，但真正稀缺的是把数据转化为理解与行动的服务能力。")
    add_figure(doc, assets["market"], 15.4, "图3　2025年中国腕戴设备出货量", "柱状图显示智能手表5061万台、手环2329万台、腕戴设备合计7390万台。",
               "IDC《中国可穿戴设备市场季度跟踪报告》公开摘要，2026年3月10日。", "https://www.idc.com/resource-center/blog/2025%E5%B9%B4%E4%B8%AD%E5%9B%BD%E8%85%95%E6%88%B4%E8%AE%BE%E5%A4%87%E5%B8%82%E5%9C%BA%E5%90%8C%E6%AF%94%E5%A2%9E%E9%95%BF20-8%EF%BC%8C%E4%BF%83%E9%94%80%E8%A1%A5%E8%B4%B4%E5%AF%B9%E5%B8%82%E5%9C%BA/")
    add_body(doc, "IDC数据显示，2025年中国腕戴设备出货量为7390万台，同比增长20.8%，其中智能手表5061万台、手环2329万台。该数据只能说明硬件市场活跃度，不能直接等同于知衡的活跃用户或可付费用户规模。")
    add_callout(doc, "行业判断", "硬件解决了“有没有数据”，知衡聚焦“数据是否可靠、怎样解释、下一步做什么、做完如何验证”。")
    add_body(doc, "硬件普及并不会自动带来健康行为改变。JAMA发表的IDEA随机临床试验纳入471名成年人，在统一生活方式干预基础上增加可穿戴技术的组别，24个月减重结果反而更低。该研究不能直接外推到知衡，也不能否定所有可穿戴产品，但提醒项目必须把“拥有设备”与“形成有效行动”区分开来，并用真实用户验证检验知衡闭环。")
    three_line_table(doc, ["行业环节", "已有供给", "仍待解决的断点", "知衡切入点"], [
        ["数据采集", "智能手表、手环和手机健康平台", "断档、来源变化、设备未佩戴容易被误读", "质量守门与来源追溯"],
        ["信息展示", "趋势、评分、摘要和单项指标", "用户难理解变化是否与自己相关", "个人基线和时间范围"],
        ["解释建议", "规则提示、内容推荐和通用AI", "事实与推测混合，建议多而泛", "事实包、一个追问、一个行动"],
        ["行为执行", "目标、打卡和提醒", "计划负担高，停止后经验无法沉淀", "3—7天低风险微计划"],
        ["结果验证", "完成率或简单前后对比", "容易忽视数据质量和主观感受，形成伪因果", "多维评估与个人方法资产"],
    ], [1.6, 2.7, 3.2, 2.5], 7.3)
    end_page(doc)

    # 8
    add_page_title(doc, "04", "用户问题：数据丰富，理解与行动仍然不足", "公开研究支持“多应用、信息过载、解释不足、行动性不足”这一问题方向。")
    add_figure(doc, assets["research"], 16.0, "图4　公开研究呈现的三个需求信号", "三个灰度数据卡：31%成年人活动不足、51%受访者使用多个健康应用、仅9%的数字健康技术研究过可理解性或可行动性。")
    add_body(doc, "IEEE Access一项56人用户调查发现，51%的参与者需要使用多个mHealth应用来满足健康追踪目标，用户偏好“图表＋文字解释”，并将信息过载、图表难读列为主要问题。JMIR 2024年范围综述覆盖83项研究、164种传感型数字健康技术，其中只有14种（9%）评估了用户能否理解信息或知道下一步如何行动。")
    add_body(doc, "一项对16名国际专家的定性访谈进一步指出，可穿戴设备产生的数据与其在健康情境中的有意义解释之间仍存在缺口，数据来源和质量是实际应用的核心问题。")
    add_source(doc, "WHO Physical activity；IBM Research/IEEE Access用户调查；JMIR Human Factors范围综述；JMIR可穿戴数据定性访谈。完整条目见附录A。")
    end_page(doc)

    # 9
    add_page_title(doc, "05", "目标用户与高价值场景", "面向广大成年用户，第一阶段以高频产生健康数据、又有明确生活方式改善需求的人群切入。")
    three_line_table(doc, ["重点人群", "典型情境", "核心困惑", "知衡价值"], [
        ["大学生", "考试、竞赛、项目冲刺", "为什么最近精力下降、睡眠波动？", "识别趋势并给出低负担的作息微计划"],
        ["青年职场人", "久坐、加班、高压力", "数据看到了，但不知道怎么改", "把状态与情境转化为一个可执行行动"],
        ["运动入门人群", "训练习惯建立、恢复观察", "单日指标波动是否需要调整？", "用个人基线和数据质量减少误判"],
        ["睡眠困扰人群", "作息不稳、日间疲劳", "哪些生活因素值得优先尝试？", "用3—7天计划形成可回看的个人证据"],
        ["关注家庭健康者", "帮助家人改善生活方式", "如何记录并回顾长期经验？", "沉淀可解释、可分享的方法资产"],
    ], [1.7, 2.4, 2.8, 3.1], 7.9)
    add_body(doc, "第一版产品仍以iPhone和用户授权的Apple Health数据为实现边界；“面向广大成年用户”是长期愿景，不代表当前已经覆盖所有设备品牌、地区或特殊医疗人群。")
    add_callout(doc, "明确不服务的边界", "第一版不针对儿童、孕产期、复杂慢病治疗、术后康复或持续医学监护设计，不提供疾病诊断、处方与药物剂量调整。")
    end_page(doc)

    # 10
    add_page_title(doc, "06", "用户调研：已有公开证据与一手验证计划", "本版已经完成公开资料调研；团队一手用户研究应在提交终稿前真实执行并补齐原始记录。")
    three_line_table(doc, ["研究层级", "方法与样本", "当前状态", "要回答的问题"], [
        ["公开二手研究", "WHO、IDC、JMIR、IEEE/JAMA及竞品官方资料", "已完成并可追溯", "行业是否增长、数据是否易懂、设备能否自动带来行为改变"],
        ["半结构化访谈", "建议8—12名成年用户，每人30—45分钟", "拟开展", "何时看数据、为何困惑、什么建议愿意尝试、哪些表达引发焦虑"],
        ["问卷筛选", "建议30—50名成年用户", "拟开展", "使用设备、查看频率、痛点优先级、隐私顾虑与行动意愿"],
        ["可用性测试", "建议5—8名用户完成4个核心任务", "拟开展", "能否理解数据不足、个人基线、微计划和AI边界"],
        ["短期日记研究", "建议5—7天，记录感受、情境与行动", "拟开展", "主客观输入是否可坚持、计划反馈是否有价值"],
    ], [2.0, 2.7, 1.7, 3.6], 7.8)
    add_callout(doc, "禁止替代", "公开研究可以帮助形成问题假设，但不能替代团队在中国校园与青年职场场景中的一手调研。最终版必须附真实招募、知情说明、原始记录、分析过程与样本限制。")
    end_page(doc)

    # 11
    add_page_title(doc, "07", "用户旅程：从“看到数字”到“形成方法”")
    three_line_table(doc, ["旅程阶段", "用户心理", "产品支持", "成功信号"], [
        ["数据积累", "拥有很多记录，不知道哪些重要", "整合授权数据并检查覆盖率、来源和断档", "用户理解当前数据是否足够"],
        ["发现变化", "担心单日异常，或忽视长期变化", "以7天窗口对照28天个人基线", "用户知道变化幅度与时间范围"],
        ["理解状态", "想知道“为什么”但不希望被诊断", "主客观对照、一个关键追问、事实/解释/不确定性分层", "用户能复述事实与可能因素的区别"],
        ["尝试行动", "大计划难坚持，泛化建议缺乏针对性", "推荐一个3—7天低风险微计划", "用户愿意确认、执行或随时停止"],
        ["验证效果", "不知道行动是否适合自己", "比较完成率、反馈、趋势和数据质量", "用户形成继续、调整或停止的判断"],
        ["沉淀方法", "过去经验容易遗忘", "多次结果一致后形成个人方法资产", "用户能回顾“什么情境下对我可能有帮助”"],
    ], [1.6, 2.5, 3.6, 2.3], 7.6)
    add_callout(doc, "北极星价值", "不是让用户每天查看更多指标，而是让用户每周至少完成一次有依据的理解与行动。")
    end_page(doc)

    # 12
    add_page_title(doc, "08", "产品方案：洞察—行动—验证的长期闭环")
    add_figure(doc, assets["closed_loop"], 16.4, "图5　知衡产品闭环", "从健康数据开始，经质量、基线、主客观洞察、微计划、效果评估，最终形成个人方法资产。")
    add_label_paragraph(doc, "数据层", "读取用户授权的运动、睡眠、心率、HRV、呼吸、血氧、腕温、步态与心肺适能等聚合信息；真实与演示数据严格分开。")
    add_label_paragraph(doc, "洞察层", "本地程序先计算数据质量、28天个人基线与趋势，AI再解释事实、表达不确定性并提出最多一个关键追问。")
    add_label_paragraph(doc, "行动层", "用户确认后才创建一个3—7天微计划，可暂停、恢复或提前结束；每日完成或跳过可附带简短感受。")
    add_label_paragraph(doc, "评估层", "计划结束后综合完成率、主观反馈、冻结基线、当前趋势和数据质量，只使用非因果、低焦虑结论。")
    three_line_table(doc, ["示例步骤", "系统发生什么", "用户看到什么"], [
        ["1 数据进入", "读取用户授权的聚合健康记录，按天处理来源与有效性", "明确是真实数据、演示数据还是权限/记录不足"],
        ["2 形成事实", "计算28天个人基线、最近7天窗口、覆盖率和变化幅度", "看到时间范围、基线、当前值和证据质量"],
        ["3 补足情境", "读取精力、压力、身体感受与用户主动添加的生活事件", "最多回答一个关键追问，不被长问卷打断"],
        ["4 推荐行动", "从低风险白名单中选择与事实匹配的一个候选计划", "确认、修改开始日期、拒绝或随时停止"],
        ["5 结束评估", "对照冻结基线、完成率、反馈、趋势和质量", "得到可能有帮助/不足以判断等审慎结论"],
    ], [1.7, 4.8, 3.5], 7.5)
    add_callout(doc, "体验设计原则", "每一步都让用户知道“系统使用了什么信息、没有使用什么信息、结论有多确定、下一步由谁决定”。")
    end_page(doc)

    # 13
    add_page_title(doc, "09", "产品展示：今日与洞察", "以下均为知衡演示模式真实页面截图，已转换为黑白，不包含用户真实健康记录。")
    add_phone_pair(doc, ASSET_DIR / "zhiheng-home-gray.png", ASSET_DIR / "zhiheng-insights-gray.png",
                   "图6　今日页：明确标记演示数据，展示目标完成度、身体状态和当日重点。",
                   "图7　洞察页：以HRV个人参考与长期趋势解释状态，不等同于医学诊断。")
    add_source(doc, "知衡项目演示模式，iPhone模拟器截图，2026年9月1日。")
    end_page(doc)

    # 14
    add_page_title(doc, "09", "产品展示：微计划与AI助手", "用户在AI助手中确认候选计划后，计划才会进入CareKitStore行动闭环。")
    add_phone_pair(doc, ASSET_DIR / "zhiheng-plan-gray.png", ASSET_DIR / "zhiheng-ai-gray.png",
                   "图8　微计划页：从一个真正做得到的小行动开始，计划事实由CareKitStore记录。",
                   "图9　AI助手页：围绕用户授权数据、近期趋势和低风险微计划展开对话。")
    add_source(doc, "知衡项目演示模式，iPhone模拟器截图，2026年9月1日。")
    end_page(doc)

    # 15
    add_page_title(doc, "10", "功能体系：五个页面共同完成一个任务")
    three_line_table(doc, ["页面", "首要任务", "核心能力", "安全设计"], [
        ["今日", "十秒内理解当前状态", "共享健康快照、目标完成度、身体卡、今日变化", "演示/真实清晰标识；不做健康总分"],
        ["洞察", "理解变化与依据", "个人基线、7/28天趋势、十类身体指标", "数据不足不输出强结论；状态不只靠颜色"],
        ["AI助手", "用自然语言理解记录", "事实包、连续对话、最多一个追问、微计划候选", "诊断/用药/急症独立规则；结构校验"],
        ["微计划", "把洞察变成行动", "十类模板、开始/暂停/恢复/结束、每日反馈、结束评估", "一次一个、低风险、可停止、不表达因果"],
        ["我的", "管理数据与设置", "数据状态、来源、权限、隐私、密钥、产品说明", "本地优先、最小权限、删除与分发边界"],
    ], [1.2, 2.1, 4.1, 2.6], 7.7)
    add_body(doc, "页面不是五个互不相关的功能集合，而是共享同一套领域事实：今日与洞察消费同一健康快照，AI只接收本地事实包，微计划执行事实只来自CareKitStore，分析快照通过稳定ID关联而不重复保存打卡状态。")
    end_page(doc)

    # 16
    add_page_title(doc, "11", "数据质量与个人基线：先判断能不能说，再决定说什么")
    three_line_table(doc, ["质量信号", "处理规则", "用户表达"], [
        ["有效日不足", "最近7天少于4个有效日，或28天少于14个有效日，不形成强趋势/基线", "当前数据不足，建议继续观察"],
        ["缺失或断档", "缺失不按0处理；记录断档不自动等同于健康下降", "近期记录不完整"],
        ["来源变化", "标记设备/来源切换，不与历史直接混比", "数据来源发生变化，暂不下结论"],
        ["单日异常", "使用中位数、MAD和多数有效日同向等稳健规则", "单日波动不代表持续变化"],
        ["质量达标", "保存时间范围、样本数、覆盖率、基线值、当前值和阈值版本", "出现值得继续观察的持续变化"],
    ], [2.0, 5.2, 2.8], 8.0)
    add_body(doc, "个人基线默认使用最近28个日历日，在至少14个有效日时计算中位数和中位绝对偏差（MAD）；短期变化使用最近7天窗口，在至少4个有效日时才进入趋势判断。所有门槛集中配置、固定输入产生固定输出，AI不得重写这些程序事实。")
    add_callout(doc, "差异化不是一个阈值", "Fitbit、Oura、WHOOP等产品也使用个体基线。知衡的创新在于把数据质量、个人基线、主观感受、生活情境、微计划执行和效果评估组合成可追溯闭环。")
    end_page(doc)

    # 17
    add_page_title(doc, "12", "趋势与AI洞察：确定性事实＋受控自然语言")
    three_line_table(doc, ["层级", "由谁负责", "输出"], [
        ["数据标准化", "HealthKit适配与领域模型", "单位、时间、来源、有效样本"],
        ["质量与基线", "本地确定性算法", "有效日、覆盖率、断档、28天中位数与MAD"],
        ["趋势事实", "本地趋势引擎", "当前值、基线值、变化幅度、持续性和不确定性"],
        ["洞察表达", "AI解释引擎", "事实、可能因素、其他可能性、一个行动或追问"],
        ["输出校验", "客户端安全层", "事实引用检查、结构校验、医疗边界与失败降级"],
    ], [2.1, 3.0, 4.9], 8.2)
    add_body(doc, "第一版趋势仅使用“未见明确变化”“值得继续观察”“存在持续变化”三档，不提供综合健康分或疾病风险分。AI无法绕过事实包新增数值；模型失败、超时或结构错误时，产品保留本地规则摘要。")
    add_callout(doc, "解释原则", "事实、解释和建议分层。生活事件与指标同期出现只能写为“可能相关”，不能写成确定原因。")
    end_page(doc)

    # 18
    add_page_title(doc, "13", "技术架构：系统边界清晰、数据职责唯一")
    add_figure(doc, assets["architecture"], 15.8, "图10　知衡分层技术架构", "四层架构：产品与交互层、应用服务层、领域与分析层、基础设施层。")
    add_body(doc, "展示层不直接散落访问HealthKit、CareKitStore或模型厂商SDK；服务协议把真实数据、演示数据和测试Fixture统一起来。领域与分析层保持纯Swift、确定性和可测试。")
    three_line_table(doc, ["事实来源", "唯一职责", "不得重复承担"], [
        ["HealthKit", "客观健康记录的授权读取与来源信息", "不保存为另一套原始样本数据库"],
        ["CareKitStore", "微计划、任务、日程、Outcome与执行历史", "SwiftData不重复保存打卡事实"],
        ["SwiftData", "主观记录、生活事件、洞察、分析快照和有效方法", "不替代CareKit版本历史"],
        ["AI服务", "解释结构化事实、追问与白名单行动建议", "不成为趋势或医学事实来源"],
    ], [2.0, 4.6, 3.4], 8.0)
    end_page(doc)

    # 19
    add_page_title(doc, "14", "安全可信AI：最小事实包、独立规则、失败可降级")
    add_figure(doc, assets["ai_flow"], 15.9, "图11　AI数据边界与安全流程", "设备本地完成聚合、质量与基线计算，仅向AI服务发送最小化事实包，AI输出还需客户端校验。")
    three_line_table(doc, ["安全控制", "具体措施"], [
        ["最小化数据", "默认不上传原始HealthKit样本数组、真实姓名、联系方式、精确地址和无关日期。"],
        ["输入预检", "诊断、药物调整、胸痛、严重呼吸困难、意识异常、严重出血、疑似卒中与自伤风险优先处理。"],
        ["结构约束", "输出区分事实、可能因素、不确定性、最多一个追问、白名单行动和安全级别。"],
        ["事实校验", "引用事实包外指标、虚构数值或因果结论时不保存为正式回答。"],
        ["失败降级", "断网、超时、结构错误或用户停止时移除未验证局部内容，保留本地摘要。"],
    ], [2.2, 7.8], 8.1)
    three_line_table(doc, ["数据阶段", "最小化原则", "可追溯设计"], [
        ["授权", "只申请当前功能必要的HealthKit只读类型；拒绝授权仍可进入说明页", "记录权限状态，不把拒绝解释为健康异常"],
        ["本地计算", "原始样本用于设备端聚合，缺失不补0，异常不自动删除", "保留时间范围、来源、样本数和阈值版本"],
        ["AI请求", "只发送完成本次回答需要的聚合事实、主观记录和允许行动", "事实包可查看；模型输出必须引用事实范围"],
        ["本地保存", "健康事实、计划事实和主观事实各归唯一存储职责", "通过稳定ID关联，避免复制和状态冲突"],
        ["删除与退出", "用户可删除主观记录、生活事件、计划关联数据和AI对话", "记录删除结果，不在日志保留敏感正文"],
    ], [1.7, 5.0, 3.3], 7.4)
    add_body(doc, "当用户表达紧急症状或自伤风险时，系统不继续进行日常趋势解释或计划推荐，而是由独立安全规则直接提示立即联系当地急救、可信任的人或专业机构。该能力是风险分流，不代表知衡能够持续监护、识别所有急症或替代医疗专业人员。")
    add_callout(doc, "发布门禁", "紧急场景文案、诊断与用药拒答、锁屏通知、隐私说明和删除路径在正式发布前均需要专项测试；医疗相关提示还应接受专业人士审阅。")
    end_page(doc)

    # 20
    add_page_title(doc, "15", "微计划与行动验证：一次只改变一件小事")
    add_body(doc, "知衡针对每次洞察只推荐一个3—7天、低风险、可随时停止的微计划。当前模板覆盖下午咖啡截止、提前上床、午后步行、工作间歇活动、降低运动负荷、睡前呼吸、晨间日光、饭后散步、固定起床时间和轻柔活动。")
    three_line_table(doc, ["阶段", "系统记录", "用户控制", "评估边界"], [
        ["开始", "计划模板、周期、时间、计划前五天聚合基线", "确认后才创建，可取消", "不上传原始样本"],
        ["执行", "CareKit Schedule、完成/跳过、可选感受", "可暂停、恢复、提前结束", "不以打卡制造压力"],
        ["结束", "完成率、反馈、客观趋势、数据质量", "可主动请求AI解读", "不自动推荐下一计划"],
        ["沉淀", "多次执行方向、完成率与覆盖率", "可回看、重新尝试或停止", "单次只能算初步观察"],
    ], [1.4, 3.2, 2.4, 3.0], 8.0)
    add_callout(doc, "禁止伪因果", "允许的结论包括“可能有帮助”“暂未观察到明显变化”“执行不足”“数据不足”“主客观结果不同步”；禁止“证明有效”“一定改善”“治疗了”。")
    three_line_table(doc, ["计划类别", "当前模板示例", "适用前提", "停止/降级条件"], [
        ["作息节律", "提前上床、固定起床、晨间日光", "用户主动选择且不涉及疾病治疗", "明显不适、作息冲突或用户取消"],
        ["久坐活动", "午后步行、工作间歇活动、饭后散步", "日常低强度活动可行", "疼痛、头晕或环境不安全"],
        ["恢复调整", "降低运动负荷、轻柔活动", "只做生活方式层面的短期调整", "症状加重或需要专业训练/医疗建议"],
        ["睡前习惯", "下午咖啡截止、睡前呼吸", "不涉及停药、剂量或睡眠疾病诊断", "用户不适、无执行条件或压力增加"],
    ], [1.6, 3.1, 3.0, 2.3], 7.2)
    add_body(doc, "模板不是由模型自由生成的无限建议库，而是经过风险分级、可停止条件和文案边界约束的候选集合。AI只能在事实包允许范围内选择、解释或提出一个候选；用户确认后，计划事实才进入CareKitStore。")
    end_page(doc)

    # 21
    add_page_title(doc, "16", "五项核心竞争力")
    strengths = [
        ("01 个人基线引擎", "从群体平均判断升级为用户与过去自己的比较；保存窗口、样本数、覆盖率、中位数与MAD。"),
        ("02 数据质量守门引擎", "分析前主动识别缺失、断档、设备未佩戴、来源变化和异常波动，减少错误结论与焦虑。"),
        ("03 多模态AI健康洞察引擎", "融合客观健康数据、精力、压力、身体感受和生活情境，使解释更贴近真实生活。"),
        ("04 行动验证闭环", "一次一个微计划，以完成率、主观反馈、趋势与数据质量共同评估，逐步沉淀个人方法。"),
        ("05 安全可信AI", "隐私优先、最小化数据、结果可追溯、非诊疗边界、独立安全规则和本地降级。"),
    ]
    for title, detail in strengths:
        add_label_paragraph(doc, title, detail)
    add_callout(doc, "竞争力的整体性", "上述能力单独看并非都属于行业空白；知衡的核心优势是将五者以统一数据职责和可验证流程组合，形成从洞察到行为改变的完整产品系统。")
    three_line_table(doc, ["竞争力", "现有工程证据", "下一步用户证据"], [
        ["个人基线", "28天中位数/MAD、有效日门槛、7/28天趋势和测试Fixture", "用户能否理解“与自己比较”并减少单日焦虑"],
        ["质量守门", "缺失、断档、来源变化、异常波动和演示/真实状态", "数据不足提示是否清楚、可信且不过度打扰"],
        ["多模态洞察", "健康事实包、精力/压力/身体感受字段和情境入口", "主观记录负担、情境解释价值和追问接受度"],
        ["行动验证", "10类模板、CareKit计划、反馈、冻结基线与结束评估", "开始率、完成率、反馈填写率和再次尝试意愿"],
        ["安全可信AI", "输入预检、结构校验、流式停止、断网降级与代理测试", "用户是否理解AI边界、数据使用和紧急提示"],
    ], [2.0, 4.5, 3.5], 7.2)
    end_page(doc)

    # 22
    add_page_title(doc, "17", "系统性创新：从单点功能到可验证个人健康智能体")
    three_line_table(doc, ["创新维度", "行业常见方式", "知衡的系统性推进"], [
        ["判断依据", "统一目标、单日分数或单指标提醒", "数据质量门槛＋个人长期基线＋稳健趋势"],
        ["解释方式", "单项图表或泛化AI建议", "客观趋势＋主观感受＋生活情境＋不确定性"],
        ["行动方式", "一次给出多条建议或长期打卡", "一次一个3—7天、低风险、可停止微计划"],
        ["验证方式", "展示完成率或单次前后对比", "冻结基线、完成率、反馈、趋势、质量共同评估"],
        ["长期资产", "分数历史、聊天历史或习惯记录", "多次执行后形成个人“有效方法”证据链"],
        ["安全与信任", "依赖模型提示或免责声明", "独立安全规则、事实包、结构校验、最小上传与失败降级"],
    ], [1.8, 3.4, 4.8], 8.0)
    add_body(doc, "创新价值最终要由一手用户研究验证：用户是否更容易理解变化、是否更愿意开始行动、是否能区分相关与因果、是否认为方法库具有长期价值。")
    end_page(doc)

    # 23
    add_page_title(doc, "18", "竞品格局与竞争策略", "竞品比较只依据公开可见功能；“公开资料未见”不等于产品绝对不支持。")
    three_line_table(doc, ["代表产品", "公开可见优势", "知衡的竞争策略"], [
        ["Apple Health", "多来源健康数据、Highlights与Trends", "在系统数据基础上补充主客观解释、微计划与效果验证"],
        ["Google Health/Fitbit", "个性化基线、Readiness、趋势与AI教练", "避免单一总分，强调质量证据、情境和低风险自我实验"],
        ["Garmin", "Body Battery、Training Readiness、训练状态与运动反馈", "从专业训练扩展到普通成年人的生活方式场景"],
        ["Oura", "Readiness、睡眠/活动/压力趋势与标签", "以一个明确微计划连接洞察与执行后的多维评估"],
        ["WHOOP", "Journal与Behavior Insights，行为和恢复关联", "更短、低负担的3—7天行动；明确完成率、主观反馈和数据质量"],
        ["StressWatch", "基于HRV/RHR的压力与习惯提示，Apple Watch场景强", "不把单项HRV直接等同于压力，以多指标和个人基线守门"],
        ["通用AI", "自然语言交互与健康教育覆盖广", "AI只解释本地程序事实，不自由推断全部原始健康样本"],
    ], [1.8, 3.5, 4.7], 7.6)
    add_source(doc, "Apple、Google/Fitbit、Garmin、Oura、WHOOP官方帮助文档及StressWatch App Store公开页，访问日期2026年9月1日。完整链接见附录A。")
    end_page(doc)

    # 24
    add_page_title(doc, "19", "市场机会：从设备用户到“愿意理解并行动”的细分人群")
    add_body(doc, "知衡不直接把7390万台年度出货量当作用户规模。出货量反映供给与设备普及趋势，但其中包含换机、重复购买和不同生态，不能推导出活跃用户、iPhone用户或付费用户。")
    three_line_table(doc, ["市场口径", "定义", "当前可用证据", "下一步验证"], [
        ["TAM需求方向", "拥有可穿戴健康数据的成年用户", "IDC腕戴设备出货增长；WHO活动不足问题", "核验存量设备与健康App使用率"],
        ["SAM目标人群", "愿意授权数据、关注睡眠/活动/状态改善的iPhone成年用户", "项目已有iPhone与HealthKit实现", "问卷验证授权意愿、场景与支付意愿"],
        ["SOM首批用户", "西南科技大学及周边成年种子用户、青年职场人", "团队可触达、可开展线下可用性测试", "先完成5—10人测试，再扩大到30—50人"],
    ], [1.8, 3.6, 2.8, 1.8], 7.8)
    add_callout(doc, "市场估算原则", "先以可触达用户和真实转化漏斗建立SOM，再逐步外推；不使用“全国成年人×假定付费率”的夸大算法。")
    add_label_paragraph(doc, "首批漏斗", "可触达成年用户 → 愿意了解产品 → 愿意使用演示数据完成任务 → 愿意授权真实数据 → 完成一次微计划 → 愿意再次使用或推荐。每一层只记录真实人数和流失原因。")
    add_body(doc, "市场验证首先判断“问题是否足够重要、产品是否足够可信、使用是否足够轻量”，随后才讨论价格。若用户不愿授权真实健康数据，团队仍可通过演示模式验证理解路径，但必须把“看懂产品”与“真实使用意愿”分开统计。")
    end_page(doc)

    # 25
    add_page_title(doc, "20", "市场进入路径：校园验证—场景深化—生态拓展")
    three_line_table(doc, ["阶段", "目标", "主要动作", "关键指标"], [
        ["校园种子验证", "确认产品是否可理解、低焦虑、愿意行动", "访谈、问卷、任务测试、短期日记研究", "任务成功率、行动开始率、焦虑反馈"],
        ["睡眠/久坐场景深化", "验证高频场景的留存价值", "迭代微计划模板和趋势解释", "7日留存、计划完成率、反馈填写率"],
        ["青年职场扩展", "验证跨人群可迁移性", "联合社群、校园就业与创新平台招募", "活跃率、洞察有帮助比例、转介绍"],
        ["多设备研究", "降低单一生态边界", "评估授权、数据口径和质量规则的分级适配", "可用数据覆盖与一致性"],
        ["组织服务探索", "验证校园/企业健康促进价值", "仅在用户授权、脱敏和合规前提下试点", "参与率、完成率、隐私投诉为零"],
    ], [1.7, 2.4, 3.6, 2.3], 7.8)
    add_body(doc, "早期增长不依赖大量广告投放，而依靠真实可用性证据、健康科普内容、场景化微计划和学校创新创业资源。所有对外传播都避免承诺医疗效果。")
    three_line_table(doc, ["触达渠道", "适合内容", "验证指标", "合规要求"], [
        ["校园创新与健康活动", "演示体验、可用性任务和匿名问卷", "报名—完成—授权—计划漏斗", "18岁以上、自愿参加、可退出"],
        ["学生与青年职场社群", "睡眠、久坐、运动入门的低焦虑科普", "内容到体验的转化与负面反馈", "不制造健康焦虑、不暗示诊断"],
        ["开发者与设计社区", "数据质量、HealthKit、CareKit和可信AI实践", "技术反馈、合作线索和开源合规", "不公开密钥、真实健康数据或受限代码"],
        ["学校/企业试点", "自愿参与的生活方式改善工具", "参与率、完成率、投诉与退出", "个人数据不向组织披露，先做合规评估"],
    ], [2.0, 3.2, 2.5, 2.3], 7.2)
    end_page(doc)

    # 26
    add_page_title(doc, "21", "商业模式：先验证价值，再验证付费")
    three_line_table(doc, ["层级", "可能提供的价值", "收费逻辑", "当前边界"], [
        ["基础免费", "数据接入、基础趋势、数据质量、少量微计划", "降低体验门槛", "第一阶段以产品验证为主"],
        ["个人增值", "长期趋势、更多情境洞察、AI对话、方法资产与报告", "订阅或按周期服务", "价格与付费率待真实调研"],
        ["组织服务", "校园/企业健康促进与匿名聚合运营支持", "项目制或席位制", "不得向组织暴露个人健康数据"],
        ["合作生态", "与合规健康服务、保险或设备平台的能力连接", "技术或服务合作", "不以付费影响医疗建议排序"],
    ], [1.6, 3.3, 2.3, 2.8], 7.8)
    add_label_paragraph(doc, "单位经济模型", "年度收入＝活跃用户×付费转化率×年均付费额；年度贡献＝收入－AI调用、服务、内容审核、合规与运营成本。所有参数在一手调研后再填，不在本版虚构。")
    add_label_paragraph(doc, "商业底线", "不出售健康数据、不做健康数据广告、不将用户数据用于训练基础模型、不夸大疾病预防或治疗效果。")
    add_callout(doc, "创意组表达", "本版重点证明商业逻辑可行和验证路径清晰，而不是伪造营收、订单、融资或用户量。")
    three_line_table(doc, ["成本类别", "主要构成", "控制策略"], [
        ["研发与测试", "iOS、健康数据、AI服务、质量保障和兼容性", "模块化协议、自动化测试、分阶段发布"],
        ["AI与网络", "模型调用、代理服务、日志与故障监控", "事实包最小化、缓存与本地降级、限额控制"],
        ["内容与安全", "低风险模板、文案审阅、红线场景和用户支持", "白名单模板、版本化规则和专业复核"],
        ["隐私与合规", "权限说明、删除机制、安全评估和材料审查", "隐私设计前置，避免后期高成本返工"],
        ["获客与运营", "用户研究、种子活动、反馈整理和留存运营", "先依托可触达场景验证，不进行大额投放"],
    ], [2.0, 4.6, 3.4], 7.3)
    end_page(doc)

    # 27
    add_page_title(doc, "22", "研发基础与工程证据", "知衡已经从概念进入可运行原型阶段，但工程测试不等于临床或大规模用户验证。")
    add_figure(doc, assets["evidence"], 15.8, "图12　截至2026年9月1日的工程证据", "四个指标卡：162项iOS测试、14项AI代理测试、10类低风险计划模板、16类健康指标聚合映射。")
    three_line_table(doc, ["模块", "已完成事实", "剩余工作"], [
        ["健康数据", "HealthKit授权与16类数据映射、真实/演示Provider、共享快照", "新增权限真机可见性与跨来源长期验证"],
        ["洞察", "数据质量、28天个人基线、7/28天详情趋势、今日变化", "完成全套趋势引擎和主观/生活事件正式数据"],
        ["AI", "DeepSeek Responses API、SSE流式回答、事实包、安全校验、降级", "真实网络、密钥、模型质量与专业文案审阅"],
        ["微计划", "十类模板、CareKitStore、暂停恢复、反馈、冻结基线、结束评估", "计划更新、跨天、删除与历史一致性"],
    ], [1.6, 5.1, 3.3], 7.8)
    three_line_table(doc, ["验证层级", "已经执行", "代表性边界", "可复核产物"], [
        ["算法单元测试", "数据质量、个人基线、趋势、计划评估等确定性用例", "稳定、上升、下降、异常、数据不足和断档", "测试代码与固定Fixture"],
        ["应用自动化测试", "累计162项iOS测试", "页面状态、持久化、计划流程、安全边界和回归", "测试报告与开发日志"],
        ["AI代理测试", "14项后端代理测试", "鉴权、请求、流式转发、错误处理和停止", "代理测试脚本与结果"],
        ["构建验证", "Debug构建、Release通用真机构建", "依赖解析、编译、签名边界和资源完整性", "构建日志与产物记录"],
        ["实际交互", "模拟器核心流程、重启后状态与演示截图", "演示/真实模式、导航、AI、计划和历史", "截图、视频候选和验收记录"],
    ], [2.0, 3.0, 3.0, 2.0], 7.1)
    add_body(doc, "测试数量反映工程覆盖，不直接代表产品没有缺陷。团队仍需完成S10-12计划更新、跨天、删除与历史一致性，并用真实设备和不同数据覆盖状态验证授权、来源变化、断网、AI失败和计划跨日行为。只有验证完成、日志记录和文档同步三者同时满足，任务才进入已完成状态。")
    add_callout(doc, "证据分层", "工程证据证明“做得出来、能够稳定运行”；一手用户证据证明“用户看得懂、愿意使用”；专业与合规审阅证明“边界足够安全”。三类证据不能相互替代。")
    add_source(doc, "知衡项目AGENTS.md、实施总方案与2026-09-01开发日志。")
    end_page(doc)

    # 28
    add_page_title(doc, "23", "用户验证计划：把工程可用转化为用户证据")
    three_line_table(doc, ["验证任务", "样本与方法", "成功指标", "风险控制"], [
        ["概念理解", "8—12名访谈＋30—50名问卷", "用户能复述痛点、价值和使用顾虑", "记录样本结构与反例，不只筛选支持观点"],
        ["可用性", "5—8名用户完成授权、看洞察、选计划、看评估", "核心任务成功率、错误点和耗时", "使用演示数据，不收集原始个人记录"],
        ["低焦虑表达", "比较不同文案并询问感受", "用户区分相对基线与医学异常", "发现恐惧或误解立即修订"],
        ["行为闭环", "5—7天日记和微计划试用", "行动开始率、完成率、反馈负担", "允许随时停止，不以完成率施压"],
        ["长期价值", "计划结束访谈与2周回访", "是否愿意回看、再次执行或沉淀方法", "不把短期变化写成健康效果"],
    ], [1.7, 3.0, 2.5, 2.8], 7.6)
    add_callout(doc, "终稿证据包", "匿名化招募说明、同意记录、访谈提纲、问卷、任务脚本、原始记录索引、编码表、负面发现和产品迭代对照。")
    end_page(doc)

    # 29
    add_page_title(doc, "24", "实施路线图")
    add_figure(doc, assets["roadmap"], 16.0, "图13　知衡项目近期实施路线图", "时间线从2026年7至8月工程闭环，延伸到9月历史一致性、一手用户验证，以及10至11月迭代和答辩。")
    three_line_table(doc, ["里程碑", "放行条件"], [
        ["稳定演示版", "S10-12历史一致性完成；核心流程重启、跨天、删除后状态正确；断网降级可演示。"],
        ["一手调研版", "访谈、问卷和可用性测试真实完成；负面发现和样本限制进入计划书。"],
        ["省赛材料版", "项目计划书、PPT、演示视频、原创性说明、开源与隐私材料一致。"],
        ["总决赛准备版", "至少三次计时彩排；评委问答覆盖创新、商业、医疗边界、隐私和团队贡献。"],
    ], [2.3, 7.7], 8.2)
    end_page(doc)

    # 30
    add_page_title(doc, "25", "团队与协作机制")
    three_line_table(doc, ["角色", "成员信息", "当前可确认事实"], [
        ["项目负责人", "陈维阳", "负责项目总体统筹；具体专业背景、成果和实质贡献由学校材料核验。"],
        ["项目成员", "李思磊", "团队成员；具体职责、专业、论文、专利和获奖信息待本人确认。"],
        ["项目成员", "杜浩天", "团队成员；具体职责、专业、论文、专利和获奖信息待本人确认。"],
        ["项目成员", "陈风博弈", "团队成员；具体职责、专业、论文、专利和获奖信息待本人确认。"],
        ["项目成员", "张潼心", "团队成员；具体职责、专业、论文、专利和获奖信息待本人确认。"],
        ["项目成员", "王奥", "团队成员；具体职责、专业、论文、专利和获奖信息待本人确认。"],
        ["指导教师", "待学校确认", "不得在未取得本人同意和学校审核前填入姓名、职称或贡献。"],
    ], [1.6, 2.1, 6.3], 7.8)
    add_label_paragraph(doc, "建议协作模块", "产品与用户研究、iOS与健康数据、AI与后端、安全与测试、视觉与材料、市场与运营。具体映射必须由团队按真实投入确认。")
    add_callout(doc, "2026规则新增强调", "团队成员及指导教师的实质性贡献属于评审内容。最终稿应为每人补充“具体任务—产出文件/代码—验证证据—投入时间”，避免只列姓名。")
    three_line_table(doc, ["协作节奏", "会议/产物", "完成标准"], [
        ["每周计划", "一页本周目标、负责人、截止时间和依赖", "每人只有可验证任务，不以模糊“协助”代替责任"],
        ["中期评审", "产品演示、研究进度、风险清单和材料差异", "问题有负责人、优先级和下一次复核时间"],
        ["功能验收", "需求、实现、正常/异常测试、截图和日志", "通过验证后才标记完成，失败与限制明确保留"],
        ["材料冻结", "Word、PPT、视频、报名系统和答辩口径对照表", "人员、数字、功能、时间和边界完全一致"],
        ["答辩复盘", "计时录像、问题清单、证据链接和改进项", "能够说明每项主张由谁完成、证据在哪里"],
    ], [2.0, 4.5, 3.5], 7.3)
    end_page(doc)

    # 31
    add_page_title(doc, "26", "社会价值、伦理与医疗边界")
    three_line_table(doc, ["价值方向", "项目贡献", "约束"], [
        ["健康素养", "帮助用户理解个人数据、时间范围、来源和不确定性", "不把图表或单项指标写成疾病判断"],
        ["行为改善", "将抽象目标拆分成可执行、可停止、可回看的微行动", "不承诺必然改善或治疗效果"],
        ["低焦虑", "数据不足、断档和单日异常时克制表达", "不以红色分数和频繁通知制造恐惧"],
        ["可信AI", "事实包、结构化输出、独立安全规则与失败降级", "不允许AI自由编造事实或调整药物"],
        ["隐私保护", "本地优先、最小权限、最小上传、可删除", "不出售健康数据或用于广告画像"],
        ["人才培养", "跨产品、软件工程、数据、AI、安全和创新创业实践", "所有成员贡献必须真实可核验"],
    ], [1.7, 4.8, 3.5], 7.8)
    add_callout(doc, "紧急场景", "用户主动描述胸痛、严重呼吸困难、意识异常、严重出血、疑似卒中或自伤风险时，独立规则优先提示立即寻求当地急救或专业帮助。知衡不承诺持续急救监护。")
    end_page(doc)

    # 32
    add_page_title(doc, "27", "风险、知识产权与开源合规")
    three_line_table(doc, ["风险", "影响", "应对"], [
        ["真实数据不足或来源变化", "趋势和演示不稳定", "质量守门、模拟数据兜底、真实/演示明确区分"],
        ["AI编造或医疗越界", "安全与信任风险", "事实包、独立规则、结构校验、固定测试和专业审阅"],
        ["用户调研不足", "个人成长与产业价值证据薄弱", "按计划执行访谈、问卷、可用性和日记研究"],
        ["范围扩张", "资源分散、核心闭环不稳定", "冻结iPhone第一版，不提前建设多端、医院或复杂商业系统"],
        ["隐私泄露", "严重合规与声誉风险", "本地优先、最小上传、脱敏、密钥管理与删除机制"],
        ["开源与原创边界不清", "原创性与参赛资格风险", "记录版本、许可证、用途，区分参考、依法复用和不采用"],
    ], [2.0, 3.0, 5.0], 7.6)
    add_body(doc, "知衡参考HealthGPT在Apple Health与大模型连接方向的开源实践，并使用Apple CareKitStore承担计划数据模型；项目原创重点是数据质量、个人基线、主客观融合、事实包、安全规则、微计划评估和个人方法资产。最终提交应附第三方开源声明。")
    three_line_table(doc, ["成果/依赖", "性质", "当前写法", "终稿证明"], [
        ["知衡品牌、交互与闭环", "团队原创成果", "按真实产品和文档描述", "设计稿、提交记录、演示视频和成员贡献"],
        ["个人基线与趋势算法", "团队实现", "描述规则、阈值、测试和适用限制", "代码、测试、版本记录和原创性说明"],
        ["Apple HealthKit", "系统框架", "作为授权健康数据来源", "官方文档与隐私说明"],
        ["Apple CareKit", "开源框架", "计划、任务、日程和Outcome唯一事实来源", "固定版本、许可证和第三方声明"],
        ["HealthGPT", "开源参考", "仅作为健康数据进入AI对话方向的研究参考", "来源、许可证、采用/不采用边界"],
        ["模型与后端服务", "外部服务能力", "经可替换AIService和代理调用", "服务条款、密钥方案、隐私评估和降级策略"],
    ], [2.3, 1.8, 3.7, 2.2], 7.0)
    end_page(doc)

    # 33
    add_page_title(doc, "28", "评分证据与待补材料", "本页是终稿前的证据看板：已完成不夸大，缺失项明确补齐。")
    three_line_table(doc, ["评分维度", "已有证据", "关键缺口", "优先动作"], [
        ["个人成长30", "工程迭代、开源研究、算法与安全测试、项目日志", "真实调研过程、成员实质贡献、导师与学校支持", "完成一手研究和贡献证据表"],
        ["项目创新30", "可运行产品、个人基线、质量守门、事实包、CareKit闭环", "真实用户效果、与强竞品的量化对比", "做任务测试与对照说明"],
        ["产业价值25", "IDC市场信号、目标人群、竞品与进入路径", "SAM/SOM实证、付费意愿、合作或试点", "问卷、访谈和校园试点"],
        ["团队协作15", "6人团队名单、负责人、协作模块框架", "成员专业、职责、成果、投入和指导教师", "逐人核验并附证明"],
        ["必要条件", "真实工程、公开来源、演示数据标识", "知识产权、财务、运营、荣誉材料尚未提供", "没有证明不写，有证明按学校审核写"],
    ], [1.6, 3.0, 3.1, 2.3], 7.3)
    add_callout(doc, "最重要的下一步", "产品功能已经明显强于当前比赛证据。下一阶段应优先把真实调研、团队贡献、试点验证和原创性证明做实，而不是继续堆叠新页面。")
    end_page(doc)

    # 34
    add_page_title(doc, "29", "结语", "知衡不是又一个健康数据看板，而是一套把数据、理解、行动和验证连接起来的个人健康智能体。")
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(28)
    p.paragraph_format.space_after = Pt(16)
    r = p.add_run("让数据成为用户改善生活质量的生产力")
    set_run_font(r, 18, bold=True)
    add_body(doc, "知衡以个人与过去的自己比较，以长期趋势而非单日波动判断状态，以真实感受和生活情境补足数据局限，以一个可执行微行动替代空泛建议，并通过结果评估沉淀属于用户自己的健康方法资产。")
    add_body(doc, "我们的目标不是替用户做出医疗判断，而是帮助用户更诚实地理解证据、更轻松地开始行动、更长期地认识自己。")
    add_callout(doc, "一句话定义", "知衡——从健康洞察到行为改变的AI个人健康智能体：把健康数据变成理解，把理解变成行动，把行动沉淀成个人方法。")
    p = doc.add_paragraph("西南科技大学｜负责人：陈维阳｜团队成员：李思磊、杜浩天、陈风博弈、张潼心、王奥")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run_font(p.runs[0], 9.2, color=MUTED)
    end_page(doc)

    # 35-36 References
    refs = [
        ("[1]", "教育部. 教育部关于举办中国国际大学生创新大赛（2026）的通知. 2026-07-31.", "https://www.moe.gov.cn/srcsite/A08/s5672/202607/t20260731_1445670.html"),
        ("[2]", "中国国际大学生创新大赛组委会. 中国国际大学生创新大赛（2026）评审规则. 2026-08-19.", "https://ieeac2015-download.oss-cn-beijing.aliyuncs.com/othersfile/%E4%B8%AD%E5%9B%BD%E5%9B%BD%E9%99%85%E5%A4%A7%E5%AD%A6%E7%94%9F%E5%88%9B%E6%96%B0%E5%A4%A7%E8%B5%9B%EF%BC%882026%EF%BC%89%E8%AF%84%E5%AE%A1%E8%A7%84%E5%88%99.pdf"),
        ("[3]", "World Health Organization. Physical activity. 2024-06-26.", "https://www.who.int/news-room/fact-sheets/detail/physical-activity"),
        ("[4]", "IDC. 2025年中国腕戴设备市场同比增长20.8%. 2026-03-10.", "https://www.idc.com/resource-center/blog/2025%E5%B9%B4%E4%B8%AD%E5%9B%BD%E8%85%95%E6%88%B4%E8%AE%BE%E5%A4%87%E5%B8%82%E5%9C%BA%E5%90%8C%E6%AF%94%E5%A2%9E%E9%95%BF20-8%EF%BC%8C%E4%BF%83%E9%94%80%E8%A1%A5%E8%B4%B4%E5%AF%B9%E5%B8%82%E5%9C%BA/"),
        ("[5]", "Alshehhi YA, et al. Understanding User Perspectives on Data Visualization in mHealth Apps: A Survey Study. IEEE Access, 2023.（56人调查）", "https://research.ibm.com/publications/understanding-user-perspectives-on-data-visualization-in-mhealth-apps-a-survey-study"),
        ("[6]", "Poncette AS, et al. Human Factors, Human-Centered Design, and Usability of Sensor-Based Digital Health Technologies: Scoping Review. JMIR, 2024.", "https://www.jmir.org/2024/1/e57628/"),
        ("[7]", "Azodo I, et al. Opportunities and Challenges Surrounding the Use of Data From Wearable Sensor Devices in Health Care: Qualitative Interview Study. JMIR, 2020.", "https://www.jmir.org/2020/10/e19542/"),
        ("[8]", "Jakicic JM, et al. Effect of Wearable Technology Combined With a Lifestyle Intervention on Long-term Weight Loss: IDEA Randomized Clinical Trial. JAMA, 2016.", "https://jamanetwork.com/journals/jama/fullarticle/2553448"),
        ("[9]", "Apple Support. View your data in Health on iPhone. 访问日期：2026-09-01.", "https://support.apple.com/guide/iphone/view-your-health-data-iphe3d379c32/26/ios/26"),
        ("[10]", "Google Health Help. Understanding your readiness score. 访问日期：2026-09-01.", "https://support.google.com/googlehealth/answer/14236710?hl=en"),
        ("[11]", "Garmin Support. Training Status / Training Readiness / Body Battery. 访问日期：2026-09-01.", "https://support.garmin.com/en-GB/?faq=VxKazDQ2mkAmDoQbJriEBA"),
        ("[12]", "Oura Member Care. Using Trends / Readiness Score. 访问日期：2026-09-01.", "https://support.ouraring.com/hc/articles/360055983614-Using-Trends"),
        ("[13]", "WHOOP. Behavior Insights / Recovery Impacts. 2026.（明确为关联而非因果）", "https://www.whoop.com/us/en/thelocker/a-new-way-to-see-insights-on-which-behaviors-affect-your-recovery/"),
        ("[14]", "StressWatch: AI Stress Monitor. Apple App Store公开页. 访问日期：2026-09-01.", "https://apps.apple.com/us/app/stresswatch-ai-stress-monitor/id6444737095"),
        ("[15]", "Apple Developer. HealthKit Documentation / Protecting User Privacy. 访问日期：2026-09-01.", "https://developer.apple.com/documentation/healthkit/protecting-user-privacy"),
        ("[16]", "CareKit. Apple开源仓库，项目当前固定版本4.1.0. 访问日期：2026-09-01.", "https://github.com/carekit-apple/CareKit"),
    ]
    add_page_title(doc, "附录A", "参考资料（1/2）")
    for num, title, url in refs[:8]:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(7)
        r = p.add_run(num + " " + title + " ")
        set_run_font(r, 8.7)
        add_hyperlink(p, "链接", url)
    end_page(doc)
    add_page_title(doc, "附录A", "参考资料（2/2）")
    for num, title, url in refs[8:]:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(7)
        r = p.add_run(num + " " + title + " ")
        set_run_font(r, 8.7)
        add_hyperlink(p, "链接", url)
    add_callout(doc, "引用说明", "所有市场、研究与竞品功能判断均应在提交前再次访问核验。公开研究样本与场景存在限制，不应直接外推为知衡目标用户的真实结论。")
    end_page(doc)

    # 37
    add_page_title(doc, "附录B", "用户问卷与访谈提纲")
    add_body(doc, "问卷建议仅面向18岁以上成年人，并在开头说明用途、匿名方式、预计耗时、退出权利和不收集原始健康数值。以下问题用于真实调研，不是已经取得的调研结果。")
    three_line_table(doc, ["模块", "建议问题"], [
        ["基本筛选", "年龄段；是否使用智能手表/手环；使用时长；主要查看睡眠、活动、心率还是恢复。"],
        ["理解负担", "看到指标变化时是否理解原因；是否需要同时使用多个App；哪些图表或分数最难理解。"],
        ["行动转化", "看到建议后是否会行动；不行动的主要原因；能接受的计划长度和每天投入。"],
        ["主观与情境", "是否愿意记录精力、压力、身体感受；愿意记录哪些生活事件；可接受频率。"],
        ["信任与焦虑", "哪些文案会引发担忧；如何看待AI解释；哪些数据不愿上传。"],
        ["价值与付费", "最有价值的能力；是否愿意试用；在什么证据下考虑付费；可接受模式。"],
    ], [2.0, 8.0], 8.0)
    add_body(doc, "访谈追问：请回忆最近一次因为手表数据产生疑问的经历；你当时做了什么；现有产品哪里有帮助、哪里没有；如果系统只让你尝试一件小事，你希望它怎样解释理由和不确定性；什么情况下你会停止使用。")
    three_line_table(doc, ["分析步骤", "具体做法", "输出"], [
        ["清理", "剔除未满18岁、明显无效或未同意研究的数据；不按预期答案筛人", "有效样本表与排除原因"],
        ["描述", "按设备使用、主要场景和人群分层统计，不把小样本百分比包装成总体规律", "样本结构与基础分布"],
        ["编码", "两名成员独立标记痛点、触发场景、行动障碍、信任和隐私主题", "编码表、分歧和合并规则"],
        ["反例", "主动记录不需要产品、拒绝授权、偏好现有工具或认为建议无价值的回答", "反例清单与产品影响"],
        ["转化", "将高频问题映射到页面、文案、流程或不做事项，并指定验证方式", "研究发现—产品改动对照表"],
        ["归档", "匿名保存同意、招募、原始记录索引、分析版本和结论限制", "可供学校核验的研究证据包"],
    ], [1.7, 5.6, 2.7], 7.1)
    add_callout(doc, "结果写法", "一手调研完成后只报告真实样本、方法、发现、反例和限制。若样本不足，只能写“初步信号”，不能写成广大大学生或青年职场人的普遍结论。")
    end_page(doc)

    # 38
    add_page_title(doc, "附录C", "最终提交核验清单")
    three_line_table(doc, ["检查项", "必须达到的状态"], [
        ["赛道与资格", "学校确认高教主赛道创意组；负责人学籍、年龄、项目历史符合2026规则。"],
        ["团队信息", "成员姓名、专业、职责、贡献、指导教师和联系方式经本人及学校核验。"],
        ["一手调研", "真实完成，样本、日期、方法、原始记录索引和限制可追溯；未完成内容删除或保持拟开展。"],
        ["项目成果", "功能状态与最新工程一致；测试数量、构建状态和截图日期准确。"],
        ["产品截图", "只使用团队自有页面；演示数据清晰标注；不含身份、密钥或原始健康记录。"],
        ["竞品与市场", "每项功能与数字有官方/同行评议来源、链接和访问日期，不夸大可服务市场。"],
        ["知识产权与开源", "只写已取得成果；附开源声明，明确HealthGPT参考和CareKit使用边界。"],
        ["财务与合作", "收入、订单、融资、合作、获奖只写有证明的事实；预测写明假设。"],
        ["医疗与隐私", "非诊疗边界、安全规则、最小化数据、删除能力与免责声明一致。"],
        ["材料一致性", "项目计划书、报名系统、PPT、视频、路演讲稿和答辩口径完全一致。"],
    ], [2.5, 7.5], 7.8)
    add_callout(doc, "最后原则", "真实、可核验、可追溯，比夸大的用户量、收入、医疗效果或“国内首创”更有说服力。")
    three_line_table(doc, ["提交文件夹", "建议内容"], [
        ["01_报名与资格", "报名系统导出、学籍与资格核验、赛道确认、团队与指导教师签字材料"],
        ["02_项目计划书", "最终Word、PDF、修改记录、数字与来源核验表"],
        ["03_产品与演示", "安装/演示说明、演示视频、关键截图、真实与演示数据说明"],
        ["04_工程证据", "测试报告、构建记录、任务清单、版本与开发日志索引"],
        ["05_用户研究", "知情说明、招募、问卷、访谈、任务脚本、匿名原始记录和分析表"],
        ["06_原创与合规", "知识产权证明、原创性说明、第三方开源声明、隐私与医疗边界材料"],
        ["07_路演与答辩", "PPT、讲稿、问答库、计时彩排记录和评委问题复盘"],
    ], [2.4, 7.6], 7.4)

    # Remove trailing page break if any and set metadata.
    doc.core_properties.title = "知衡——从健康洞察到行为改变的AI个人健康智能体｜国创赛项目计划书"
    doc.core_properties.subject = "中国国际大学生创新大赛（2026）高教主赛道创意组项目计划书"
    doc.core_properties.author = "西南科技大学知衡项目团队"
    doc.core_properties.keywords = "知衡, AI健康, 个人基线, 微计划, 行为改变, 国创赛"
    doc.core_properties.comments = "本文件为原生可编辑Word版本；演示截图不含真实健康数据。"
    doc.save(OUTPUT)
    return OUTPUT


if __name__ == "__main__":
    print(build_document())
