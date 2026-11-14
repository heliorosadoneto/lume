#!/usr/bin/env python3
"""Prévia do ícone e da splash do Lume como apareceriam no celular (1080x2400,
densidade 2.75 como o moto g9 plus). Usa os PNGs gerados por make_icon.py.

    python3 tool/make_icon_previews.py [pasta-de-saída]
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'docs', 'screenshots')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'SourceSans3.ttf')
W, H, DP = 1080, 2400, 2.75
BG = (0xD4, 0x69, 0x50)
fg = Image.open(os.path.join(RES, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png')).convert('RGBA')
mono = Image.open(os.path.join(RES, 'mipmap-xxxhdpi', 'ic_launcher_monochrome.png')).convert('RGBA')


def font(size, weight=500):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def mask(size, shape):
    s4 = size * 4
    m = Image.new('L', (s4, s4), 0)
    d = ImageDraw.Draw(m)
    if shape == 'circle':
        d.ellipse((0, 0, s4 - 1, s4 - 1), fill=255)
    elif shape == 'squircle':
        d.rounded_rectangle((0, 0, s4 - 1, s4 - 1), radius=round(s4 * .32), fill=255)
    elif shape == 'rounded':
        d.rounded_rectangle((0, 0, s4 - 1, s4 - 1), radius=round(s4 * .18), fill=255)
    elif shape == 'teardrop':
        d.rounded_rectangle((0, 0, s4 - 1, s4 - 1), radius=round(s4 * .5), fill=255)
        d.rectangle((s4 // 2, s4 // 2, s4 - 1, s4 - 1), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def lume_icon(size, shape, themed=False):
    """Adaptive icon: 108dp de camada, o launcher mostra os 72dp do meio."""
    layer = mono if themed else fg
    crop = layer.crop((72, 72, 360, 360)).resize((size, size), Image.LANCZOS)
    if themed:  # Android 13: fundo claro do tema e a camada monocromática tingida
        icon = Image.new('RGBA', (size, size), (0xDC, 0xE4, 0xF2, 255))
        tint = Image.new('RGBA', (size, size), (0x2B, 0x3A, 0x55, 255))
        tint.putalpha(crop.getchannel('A'))
        icon.alpha_composite(tint)
    else:
        icon = Image.new('RGBA', (size, size), BG + (255,))
        icon.alpha_composite(crop)
    icon.putalpha(mask(size, shape))
    return icon


def other_icon(size, shape, color, glyph):
    """Ícones genéricos de outros apps (formas simples, sem marcas)."""
    icon = Image.new('RGBA', (size, size), color + (255,))
    d = ImageDraw.Draw(icon)
    c, r = size / 2, size * .2
    white = (255, 255, 255, 235)
    if glyph == 'circle':
        d.ellipse((c - r, c - r, c + r, c + r), outline=white, width=round(size * .07))
    elif glyph == 'square':
        d.rounded_rectangle((c - r, c - r, c + r, c + r), radius=round(r * .3), outline=white, width=round(size * .07))
    elif glyph == 'tri':
        d.polygon([(c - r, c + r * .8), (c + r, c + r * .8), (c, c - r)], fill=white)
    elif glyph == 'bars':
        for i in range(3):
            d.rounded_rectangle((c - r, c - r + i * r * .8, c + r, c - r + i * r * .8 + r * .35), radius=4, fill=white)
    elif glyph == 'dot':
        d.ellipse((c - r * .6, c - r * .6, c + r * .6, c + r * .6), fill=white)
    icon.putalpha(mask(size, shape))
    return icon


def shadow(img, radius=10, offset=6):
    s = Image.new('RGBA', (img.width + 60, img.height + 60), (0, 0, 0, 0))
    a = img.getchannel('A').point(lambda v: v * 0.35)
    blk = Image.new('RGBA', img.size, (0, 0, 0, 255))
    blk.putalpha(a)
    s.alpha_composite(blk, (30, 30 + offset))
    return s.filter(ImageFilter.GaussianBlur(radius))


def wallpaper():
    top, bot = (0x2E, 0x2A, 0x45), (0xC9, 0x7B, 0x5F)
    wp = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(wp)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(round(top[i] + (bot[i] - top[i]) * t ** 1.4) for i in range(3)))
    return wp.convert('RGBA')


def status_bar(img, color=(255, 255, 255, 235)):
    d = ImageDraw.Draw(img)
    d.text((60, 40), '21:40', font=font(44, 600), fill=color)
    for i in range(4):
        d.rectangle((W - 230 + i * 18, 78 - i * 10, W - 218 + i * 18, 86), fill=color)
    d.rounded_rectangle((W - 140, 52, W - 70, 86), radius=8, outline=color, width=4)
    d.rectangle((W - 134, 58, W - 92, 80), fill=color)


def label(img, cx, y, text, color=(255, 255, 255, 245), size=38):
    d = ImageDraw.Draw(img)
    f = font(size, 500)
    w = d.textlength(text, font=f)
    if color[0] > 128:  # sombra só no texto claro sobre o papel de parede
        d.text((cx - w / 2 + 2, y + 2), text, font=f, fill=(0, 0, 0, 90))
    d.text((cx - w / 2, y), text, font=f, fill=color)


def launcher():
    img = wallpaper()
    status_bar(img)
    d = ImageDraw.Draw(img)
    size = round(56 * DP)  # ícone de 56dp
    cols = [W * (i + .5) / 4 for i in range(4)]
    # tela inicial com máscara redonda (Pixel)
    d.text((60, 170), 'Tela inicial', font=font(46, 650), fill=(255, 255, 255, 230))
    d.text((60, 228), 'ícones redondos', font=font(36, 400), fill=(255, 255, 255, 170))
    others = [((0x3D, 0x7E, 0xD8), 'circle', 'Câmera'), ((0x38, 0xA1, 0x69), 'bars', 'Agenda'),
              ((0xE0, 0xA5, 0x2E), 'tri', 'Fotos'), ((0x6C, 0x5C, 0xC9), 'square', 'Notas'),
              ((0x2C, 0x9C, 0xA8), 'dot', 'Relógio'), ((0x8A, 0x8F, 0x99), 'bars', 'Ajustes'),
              ((0xD2, 0x4F, 0x7B), 'circle', 'Música')]
    y0 = 330
    grid = [others[0], 'lume', others[1], others[2], others[3], others[4], others[5], others[6]]
    for i, g in enumerate(grid):
        cx, y = cols[i % 4], y0 + (i // 4) * 300
        icon = lume_icon(size, 'circle') if g == 'lume' else other_icon(size, 'circle', g[0], g[1])
        img.alpha_composite(shadow(icon), (round(cx - size / 2 - 30), y - 30))
        img.alpha_composite(icon, (round(cx - size / 2), y))
        label(img, cx, y + size + 16, 'Lume' if g == 'lume' else g[2])
    # gaveta de apps com máscara squircle (Samsung, Motorola…)
    top = 1020
    panel = Image.new('RGBA', (W, H - top), (0xF6, 0xF0, 0xE4, 245))
    pm = Image.new('L', panel.size, 0)
    ImageDraw.Draw(pm).rounded_rectangle((0, 0, W - 1, H - top + 80), radius=70, fill=255)
    img.paste(panel, (0, top), pm)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((W / 2 - 60, top + 26, W / 2 + 60, top + 38), radius=6, fill=(0, 0, 0, 60))
    d.text((60, top + 70), 'Gaveta de apps', font=font(46, 650), fill=(0x2B, 0x26, 0x22))
    d.text((60, top + 128), 'ícones squircle', font=font(36, 400), fill=(0x7D, 0x71, 0x66))
    y1 = top + 230
    drawer = [('Agenda', others[1]), ('Câmera', others[0]), ('Fotos', others[2]), ('Lume', 'lume')]
    for i, (name, g) in enumerate(drawer):
        cx = cols[i]
        icon = lume_icon(size, 'squircle') if g == 'lume' else other_icon(size, 'squircle', g[0], g[1])
        img.alpha_composite(shadow(icon, 8, 4), (round(cx - size / 2 - 30), y1 - 30))
        img.alpha_composite(icon, (round(cx - size / 2), y1))
        label(img, cx, y1 + size + 16, name, color=(0x2B, 0x26, 0x22, 255))
    # outras máscaras e o ícone temático do Android 13
    y2 = y1 + 400
    d.text((60, y2 - 90), 'Outras formas e ícone temático (Android 13+)', font=font(38, 600), fill=(0x2B, 0x26, 0x22))
    shapes = [('rounded', 'Quadrado'), ('teardrop', 'Gota'), ('circle', 'Redondo'), ('themed', 'Temático')]
    for i, (sh, name) in enumerate(shapes):
        cx = cols[i]
        icon = lume_icon(size, 'circle', themed=True) if sh == 'themed' else lume_icon(size, sh)
        img.alpha_composite(shadow(icon, 8, 4), (round(cx - size / 2 - 30), y2 - 30))
        img.alpha_composite(icon, (round(cx - size / 2), y2))
        label(img, cx, y2 + size + 16, name, color=(0x2B, 0x26, 0x22, 255), size=34)
    # ícone grande para ver os detalhes
    big = round(100 * DP)
    yb = y2 + 340
    icon = lume_icon(big, 'squircle')
    img.alpha_composite(shadow(icon, 16, 8), (round(W / 2 - big / 2 - 30), yb - 30))
    img.alpha_composite(icon, (round(W / 2 - big / 2), yb))
    label(img, W / 2, yb + big + 20, 'Lume', color=(0x2B, 0x26, 0x22, 255), size=48)
    return img


def splash():
    img = Image.new('RGBA', (W, H), BG + (255,))
    icon = Image.open(os.path.join(RES, 'drawable-nodpi', 'splash_icon.png')).convert('RGBA')
    s = round(240 * DP)
    icon = icon.resize((s, s), Image.LANCZOS)
    img.alpha_composite(icon, (round(W / 2 - s / 2), round(H / 2 - s / 2)))
    status_bar(img)
    return img


os.makedirs(OUT, exist_ok=True)
launcher().convert('RGB').save(os.path.join(OUT, '38_icone_launcher.png'), optimize=True)
splash().convert('RGB').save(os.path.join(OUT, '39_splash.png'), optimize=True)
print('ok', OUT)
