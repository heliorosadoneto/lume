#!/usr/bin/env python3
"""Gera o ícone do Lume a partir de branding/lume-logo.jpg (lua de páginas com
vaga-lume em fundo terracota): adaptive icon (fundo de cor sólida + frente
recortada dentro da área segura), monocromático (ícones temáticos do Android
13), mipmaps antigos (quadrado arredondado e redondo), splash e a logo usada
dentro do app. Requer Pillow e numpy.

    python3 tool/make_icon.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'branding', 'lume-logo.jpg')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

im = Image.open(SRC).convert('RGB')
a = np.asarray(im).astype(np.float64)
h, w, _ = a.shape
yy, xx = np.mgrid[0:h, 0:w]
r, g, b = a[..., 0], a[..., 1], a[..., 2]

# 1. Fundo terracota: plano (gradiente leve) ajustado aos pixels terracota.
terra = (r > 150) & (g < 150) & (b < 125) & (r - g > 60)
glow_c = (538, 562)
far_glow = (xx - glow_c[0]) ** 2 + (yy - glow_c[1]) ** 2 > 110 ** 2
fit = terra & far_glow
A = np.c_[np.ones(fit.sum()), xx[fit], yy[fit]]
coef = [np.linalg.lstsq(A, a[..., k][fit], rcond=None)[0] for k in range(3)]
B = np.stack([c[0] + c[1] * xx + c[2] * yy for c in coef], -1)
bg = tuple(int(round(v)) for v in np.median(a[fit], axis=0))
print('cor de fundo', '#%02X%02X%02X' % bg)

# 2. Matte por diferença ao fundo, na direção do creme da lua.
F = np.array([252.0, 244.0, 228.0])
d = F - B
alpha = ((a - B) * d).sum(-1) / (d * d).sum(-1)
roi = np.zeros((h, w), bool)
roi[150:870, 190:880] = True
alpha = np.where(roi, alpha, 0)
alpha = np.clip((alpha - 0.07) / 0.93, 0, 1)

# Miolo sólido: o que passa de 0.45, sem buracos, encolhido 2 px → alfa 1.
solid = Image.fromarray(((alpha > 0.45) * 255).astype(np.uint8))
solid = solid.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
fill = solid.copy()
ImageDraw.floodfill(fill, (0, 0), 128)
holes = np.asarray(fill) == 0
solid_a = (np.asarray(solid) > 0) | holes
core = np.asarray(Image.fromarray((solid_a * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 0
alpha = np.where(core, 1.0, alpha)

# Cor da frente: tira o fundo misturado (c = B + alfa·(F' − B)).
safe = np.maximum(alpha, 1e-3)[..., None]
fg = np.clip(B + (a - B) / safe, 0, 255)
fg = np.where(core[..., None], a, fg)
rgba = np.dstack([fg, alpha * 255]).astype(np.uint8)
front = Image.fromarray(rgba, 'RGBA')

# Monocromático: só a lua e o ponto do vaga-lume (sem o brilho).
mono_a = np.where(solid_a | (alpha > 0.8), 1.0, 0.0)
mono = Image.fromarray((mono_a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))

# 3. Enquadra: centro da caixa da lua; o ponto mais distante com alfa > 0.15
#    fica a 23% do lado da camada (zona segura do adaptive icon: 33%; o
#    launcher mostra 33% a partir do centro), como no desenho original.
ys, xs = np.nonzero(alpha > 0.15)
cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
rad = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2).max()
print('lua', xs.min(), ys.min(), xs.max(), ys.max(), 'raio', round(rad))


def layer(img, size, frac=0.23, mode="RGBA"):
    """Camada quadrada `size` com o conteúdo centrado, raio = frac·size."""
    scale = frac * size / rad
    big = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    out = Image.new(mode, (size, size), (0, 0, 0, 0) if mode == 'RGBA' else 0)
    out.paste(big, (round(size / 2 - cx * scale), round(size / 2 - cy * scale)))
    return out


def composite(size, shape):
    """Ícone pronto (fundo + frente) recortado como o launcher faria."""
    s4 = size * 4
    full = Image.new('RGBA', (s4, s4), bg + (255,))
    # o adaptive tem 108dp e o launcher mostra os 72dp do meio
    fr = layer(front, round(s4 * 108 / 72))
    off = (fr.width - s4) // 2
    full.alpha_composite(fr.crop((off, off, off + s4, off + s4)))
    mask = Image.new('L', (s4, s4), 0)
    md = ImageDraw.Draw(mask)
    if shape == 'circle':
        md.ellipse((0, 0, s4 - 1, s4 - 1), fill=255)
    elif shape == 'squircle':
        md.rounded_rectangle((0, 0, s4 - 1, s4 - 1), radius=round(s4 * 0.30), fill=255)
    else:
        md.rounded_rectangle((0, 0, s4 - 1, s4 - 1), radius=round(s4 * 0.22), fill=255)
    full.putalpha(mask)
    return full.resize((size, size), Image.LANCZOS)


def save(img, *parts):
    path = os.path.join(RES, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


for name, k in DENS.items():
    save(layer(front, round(108 * k)), f'mipmap-{name}', 'ic_launcher_foreground.png')
    m = layer(mono.convert('L'), round(108 * k), mode='L')
    white = Image.new('RGBA', m.size, (255, 255, 255, 0))
    white.putalpha(m)
    save(white, f'mipmap-{name}', 'ic_launcher_monochrome.png')
    save(composite(round(48 * k), 'rounded'), f'mipmap-{name}', 'ic_launcher.png')
    save(composite(round(48 * k), 'circle'), f'mipmap-{name}', 'ic_launcher_round.png')

xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
'''
os.makedirs(os.path.join(RES, 'mipmap-anydpi-v26'), exist_ok=True)
for n in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    open(os.path.join(RES, 'mipmap-anydpi-v26', n), 'w').write(xml)
hexbg = '#%02X%02X%02X' % bg
os.makedirs(os.path.join(RES, 'values'), exist_ok=True)
open(os.path.join(RES, 'values', 'colors.xml'), 'w').write(f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{hexbg}</color>
    <color name="splash_background">{hexbg}</color>
</resources>
''')

# Splash: Android 12+ (ícone de 240dp, conteúdo no círculo de 160dp) e antigos.
save(layer(front, 960, frac=0.29), 'drawable-nodpi', 'splash_icon.png')
for name, k in DENS.items():
    save(layer(front, round(200 * k), frac=0.42), f'drawable-{name}', 'splash_logo.png')

# Logo dentro do app (quadrado arredondado, sem a borda branca do original).
assets = os.path.join(ROOT, 'assets', 'logo')
os.makedirs(assets, exist_ok=True)
composite(512, 'squircle').save(os.path.join(assets, 'lume.png'), optimize=True)
print('ok')
