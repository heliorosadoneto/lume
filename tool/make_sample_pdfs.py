"""Gera PDFs de exemplo (domínio público, Project Gutenberg) para testar o Lume.

Uso: python tool/make_sample_pdfs.py <pg.txt> <saida.pdf> --title T --author A [--no-meta] [--max-pages N]
Os textos são de Machado de Assis (domínio público). A fonte é Literata (SIL OFL), do próprio app.
"""
import argparse, re
from reportlab.lib.pagesizes import A5
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, PageBreak, Flowable
from reportlab.lib.units import mm

pdfmetrics.registerFont(TTFont('Lit', 'assets/fonts/Literata.ttf'))
pdfmetrics.registerFont(TTFont('LitI', 'assets/fonts/Literata-Italic.ttf'))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily('Lit', normal='Lit', italic='LitI', bold='Lit', boldItalic='LitI')

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('out')
ap.add_argument('--title', required=True); ap.add_argument('--author', required=True)
ap.add_argument('--year', default=''); ap.add_argument('--publisher', default='')
ap.add_argument('--start', default=r'CAPITULO I'); ap.add_argument('--chapter', default=r'CAPITULO ([IVXLC]+|PRIMEIRO)\.?')
ap.add_argument('--no-meta', action='store_true'); ap.add_argument('--max-pages', type=int, default=0)
a = ap.parse_args()

raw = open(a.src, encoding='utf-8').read()
body = raw.split('*** START OF', 1)[1].split('\n', 1)[1].split('*** END OF', 1)[0]
# começa no primeiro capítulo
m = re.search(r'\n[ \t]*\n[ \t]*' + a.start + r'[ \t]*\n[ \t]*\n', body)
body = body[m.start():]
paras = [re.sub(r'\s+', ' ', p).strip() for p in re.split(r'\n\s*\n', body)]
paras = [p for p in paras if p]

st = dict(
    body=ParagraphStyle('b', fontName='Lit', fontSize=10.2, leading=15, alignment=TA_JUSTIFY, firstLineIndent=14, textColor='#1d1a17'),
    ch=ParagraphStyle('c', fontName='Lit', fontSize=13, leading=18, alignment=TA_CENTER, spaceBefore=40, spaceAfter=22, textColor='#1d1a17'),
)

class Bookmark(Flowable):
    def __init__(s, title, key): super().__init__(); s.title, s.key = title, key
    def wrap(s, *_): return (0, 0)
    def draw(s):
        s.canv.bookmarkPage(s.key); s.canv.addOutlineEntry(s.title, s.key, level=0)

def esc(t):
    t = t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    return re.sub(r'_([^_]+)_', r'<i>\1</i>', t).replace('--', '—')

story = []
n = 0
for p in paras:
    if re.fullmatch(a.chapter, p):
        n += 1
        if n > 1: story.append(PageBreak())
        w = p.split()
        title = ('Capítulo ' + ('I' if w[-1] == 'PRIMEIRO' else w[-1].rstrip('.'))) if w[0] == 'CAPITULO' else p
        story.append(Bookmark(title, f'c{n}'))
        story.append(Paragraph(title.upper(), st['ch']))
    elif p.upper() == p and len(p) < 60:
        continue
    else:
        story.append(Paragraph(esc(p), st['body']))

W, H = A5
def cover(c, doc):
    c.saveState()
    c.setFillColor('#fbf8f1'); c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setStrokeColor('#6b4a33'); c.setLineWidth(1.2); c.rect(18, 18, W - 36, H - 36)
    c.setLineWidth(.5); c.rect(23, 23, W - 46, H - 46)
    c.setFillColor('#6b4a33')
    c.setFont('Lit', 9); c.drawCentredString(W / 2, H - 70, 'BIBLIOTHECA UNIVERSAL')
    c.setFont('Lit', 34); c.drawCentredString(W / 2, H * .62, a.title.upper())
    c.setFont('LitI', 12); c.drawCentredString(W / 2, H * .62 - 34, 'por')
    c.setFont('Lit', 15); c.drawCentredString(W / 2, H * .62 - 60, a.author.upper())
    # ornamento
    cx, cy = W / 2, H * .36
    for r in (22, 16, 4):
        c.circle(cx, cy, r, stroke=1, fill=1 if r == 4 else 0)
    c.line(cx - 70, cy, cx - 28, cy); c.line(cx + 28, cy, cx + 70, cy)
    c.setFont('Lit', 10); c.drawCentredString(W / 2, 92, 'RIO DE JANEIRO')
    if a.publisher: c.drawCentredString(W / 2, 78, a.publisher)
    if a.year: c.drawCentredString(W / 2, 62, a.year)
    c.restoreState()

def page(c, doc):
    c.saveState()
    c.setFont('LitI', 8); c.setFillColor('#6f655b')
    c.drawCentredString(W / 2, H - 28, a.title)
    c.setFont('Lit', 8.5); c.drawCentredString(W / 2, 26, str(doc.page))
    c.restoreState()

class Doc(BaseDocTemplate):
    def handle_pageEnd(s):
        super().handle_pageEnd()
        if a.max_pages and s.page >= a.max_pages:
            raise StopIteration

frame = Frame(20 * mm, 18 * mm, W - 40 * mm, H - 40 * mm, id='f')
doc = Doc(a.out, pagesize=A5, title='' if a.no_meta else a.title, author='' if a.no_meta else a.author,
          subject='' if a.no_meta else 'Domínio público · texto do Project Gutenberg', creator='Lume (amostra)')
doc.addPageTemplates([PageTemplate('cover', [Frame(0, 0, W, H)], onPage=cover),
                      PageTemplate('body', [frame], onPage=page)])
from reportlab.platypus import NextPageTemplate
story = [NextPageTemplate('body'), PageBreak()] + story
try:
    doc.build(story)
except StopIteration:
    doc.canv.save() if False else None
    # fecha o arquivo com as páginas já prontas
    doc._endBuild()
print(a.out)
