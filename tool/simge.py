#!/usr/bin/env python3
"""Uygulama simgesinin tek kaynağı.

    python3 tool/simge.py

Yazdıkları (android/app/src/main/res altında):
  drawable/ic_launcher_background.xml   uyarlanabilir simgenin zemini (kiremit, dikey geçiş)
  drawable/ic_launcher_foreground.xml   ön plan: kutu, içinde iki kart
  drawable/ic_launcher_monochrome.xml   Android 13+ tema simgesi (tek renk, aralarında boşluk)
  drawable/ic_splash.xml                Android 12 öncesi açılış ekranındaki simge
  drawable/ic_stat_envanter.xml         bildirim çubuğundaki küçük simge (aynı biçim)
  mipmap-*/ic_launcher.png              Android 7'nin (API 24–25) düz simgesi
ve build/simge/ altında önizlemeler (SVG + PNG).

Neden elle çizim değil de bu betik: SVG önizlemesi ile cihazdaki vektör aynı veriden çıksın
(yalnızca M/L/C/Z yolları; Android vektöründe bulanıklık, dönüşümlü degrade gibi şeyler yok,
onlara hiç başvurulmadı). PNG'ler için `rsvg-convert` (librsvg) gerekir.
"""
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
PREVIEW = os.path.join(ROOT, 'build', 'simge')

# ---------------------------------------------------------------- renkler

BG_TOP, BG_BOTTOM = '#DA6B42', '#B4462A'   # uygulamanın kiremidi (#C4552F) ortada kalır
BOX_TOP, BOX_BOTTOM = '#FFFBF4', '#F2E5D3'  # kağıt
HANDLE = '#B84B2A'
SHADOW = '#7A2C14'
DEEP = '#5E2410'                             # kartların kutuya giren yerindeki gölge tonu
BLUE = '#B9C7DF'                             # kart paletinden "mürekkep mavisi"
PRINT = '#FFFDF8'                            # fotoğraf baskısının kenarı
SKY, HILL, SUN = '#B4D6E4', '#9CCFB8', '#FFF4DA'


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return '#' + ''.join(f'{round(x + (y - x) * t):02X}' for x, y in zip(a, b))


# ---------------------------------------------------------------- geometri
# Yollar yalnızca ('M', p), ('L', p), ('C', c1, c2, p), ('Z',) parçalarından oluşur; dönüşümler
# noktalara uygulanır (çember yayları da kübik eğri olduğu için döndürme kayıpsız).

def _arc(o, r, a1, a2):
    """Merkezi o olan çember yayı (derece, en çok 90°) tek kübik eğri olarak."""
    t1, t2 = math.radians(a1), math.radians(a2)
    k = 4 / 3 * math.tan((t2 - t1) / 4) * r
    p1 = (o[0] + r * math.cos(t1), o[1] + r * math.sin(t1))
    p2 = (o[0] + r * math.cos(t2), o[1] + r * math.sin(t2))
    return ('C', (p1[0] - k * math.sin(t1), p1[1] + k * math.cos(t1)),
            (p2[0] + k * math.sin(t2), p2[1] - k * math.cos(t2)), p2)


def rrect(x, y, w, h, r, smooth=0.6):
    """Yumuşak köşeli dikdörtgen, saat yönünde. Köşe Figma'nın "corner smoothing"i: düz kenardan
    çembere eğrilik sıçramadan geçer (sıradan yuvarlak köşedeki "kırık" görünmez). smooth=0 düz
    çember köşe; köşe yarıçapı kısa kenarın yarısıysa (hap) yumuşatma kendiliğinden düşer."""
    budget = min(w, h) / 2
    r = min(r, budget)
    x1, y1 = x + w, y + h
    if r <= 0:
        return [('M', (x, y)), ('L', (x1, y)), ('L', (x1, y1)), ('L', (x, y1)), ('Z',)]
    p = min((1 + smooth) * r, budget)
    smooth = min(smooth, max(budget / r - 1, 0))
    al = 45 * smooth
    ar = math.radians(al)
    c = r * math.tan(ar / 2) * math.cos(ar)
    d = c * math.tan(ar)
    arc = r * (math.cos(ar) - math.sin(ar))
    b = (p - arc - c - d) / 3
    a = 2 * b
    out = [('M', (x + p, y)), ('L', (x1 - p, y))]
    # sağ üst
    out.append(('C', (x1 - p + a, y), (x1 - p + a + b, y), (x1 - p + a + b + c, y + d)))
    out.append(_arc((x1 - r, y + r), r, -90 + al, -al))
    q = out[-1][3]
    out.append(('C', (x1, q[1] + c), (x1, q[1] + b + c), (x1, y + p)))
    out.append(('L', (x1, y1 - p)))
    # sağ alt
    out.append(('C', (x1, y1 - p + a), (x1, y1 - p + a + b), (x1 - d, y1 - p + a + b + c)))
    out.append(_arc((x1 - r, y1 - r), r, al, 90 - al))
    q = out[-1][3]
    out.append(('C', (q[0] - c, y1), (q[0] - b - c, y1), (x1 - p, y1)))
    out.append(('L', (x + p, y1)))
    # sol alt
    out.append(('C', (x + p - a, y1), (x + p - a - b, y1), (x + p - a - b - c, y1 - d)))
    out.append(_arc((x + r, y1 - r), r, 90 + al, 180 - al))
    q = out[-1][3]
    out.append(('C', (x, q[1] - c), (x, q[1] - b - c), (x, y1 - p)))
    out.append(('L', (x, y + p)))
    # sol üst
    out.append(('C', (x, y + p - a), (x, y + p - a - b), (x + d, y + p - a - b - c)))
    out.append(_arc((x + r, y + r), r, 180 + al, 270 - al))
    q = out[-1][3]
    out.append(('C', (q[0] + c, y), (q[0] + b + c, y), (x + p, y)))
    out.append(('Z',))
    return out


def circle(cx, cy, r):
    return [('M', (cx + r, cy))] + [_arc((cx, cy), r, i * 90, i * 90 + 90) for i in range(4)] + [('Z',)]


def poly(points):
    return [('M', points[0])] + [('L', p) for p in points[1:]] + [('Z',)]


def rotate(deg, px, py):
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    return (c, -s, px - c * px + s * py, s, c, py - s * px - c * py)


def scale(k, px, py):
    return (k, 0, px - k * px, 0, k, py - k * py)


def then(m1, m2):
    """Önce m1, sonra m2."""
    a, b, c, d, e, f = m2
    A, B, C, D, E, F = m1
    return (a * A + b * D, a * B + b * E, a * C + b * F + c, d * A + e * D, d * B + e * E, d * C + e * F + f)


IDENTITY = (1, 0, 0, 0, 1, 0)


def apply(m, pt):
    return (m[0] * pt[0] + m[1] * pt[1] + m[2], m[3] * pt[0] + m[4] * pt[1] + m[5])


def transform(path, m):
    return [seg if seg[0] == 'Z' else (seg[0],) + tuple(apply(m, p) for p in seg[1:]) for seg in path]


def _prune(path):
    """Aynı noktaya giden parçaları atar (hap biçiminde köşe eğrileri sıfır uzunlukta kalır)."""
    out, cur = [], None
    for seg in path:
        if seg[0] in 'MZ':
            out.append(seg)
            if seg[0] == 'M':
                cur = seg[1]
            continue
        if all(abs(p[0] - cur[0]) < 1e-6 and abs(p[1] - cur[1]) < 1e-6 for p in seg[1:]):
            continue
        out.append(seg)
        cur = seg[-1]
    return out


def reverse(path):
    """Tek parçalı kapalı yolu ters yönde çizer. Sıfırdan farklı (nonZero) kuralla dolan bir yolda
    ters yönlü iç parça delik açar; SVG'de de Android vektöründe de aynı sonuç (evenOdd'a gerek yok,
    kırpma yollarında Android zaten yalnızca bu kuralı kullanır)."""
    path = _prune(path)
    segs = [s for s in path[1:] if s[0] != 'Z']
    pts = [path[0][1]] + [s[-1] for s in segs]
    out = [('M', pts[-1])]
    for i in range(len(segs) - 1, -1, -1):
        s = segs[i]
        out.append(('L', pts[i]) if s[0] == 'L' else ('C', s[2], s[1], pts[i]))
    return out + [('Z',)]


def pathdata(path):
    def n(v):
        s = f'{v:.3f}'.rstrip('0').rstrip('.')
        return '0' if s in ('-0', '') else s

    parts = []
    for seg in _prune(path):
        parts.append('Z' if seg[0] == 'Z' else seg[0] + ' '.join(f'{n(p[0])},{n(p[1])}' for p in seg[1:]))
    return ''.join(parts)


def bounds(path):
    xs = [p[0] for seg in path if seg[0] != 'Z' for p in seg[1:]]
    ys = [p[1] for seg in path if seg[0] != 'Z' for p in seg[1:]]
    return min(xs), min(ys), max(xs), max(ys)


# ---------------------------------------------------------------- çizim belgesi

class Linear:
    """Doğrusal geçiş; uçlar yolla aynı koordinatlarda (dönüşüm uçlara da uygulanır)."""

    def __init__(self, p1, p2, stops):
        self.p1, self.p2, self.stops = p1, p2, stops

    def moved(self, m):
        return Linear(apply(m, self.p1), apply(m, self.p2), self.stops)


class Shape:
    def __init__(self, path, fill, alpha=1.0, clips=()):
        self.path, self.fill, self.alpha, self.clips = path, fill, alpha, list(clips)

    def moved(self, m):
        fill = self.fill.moved(m) if isinstance(self.fill, Linear) else self.fill
        return Shape(transform(self.path, m), fill, self.alpha, [transform(c, m) for c in self.clips])


def moved(shapes, m):
    return [s.moved(m) for s in shapes]


def _argb(color, alpha=1.0):
    a = round(alpha * 255)
    if len(color) == 9:  # #RRGGBBAA
        a = round(int(color[7:9], 16) * alpha)
        color = color[:7]
    return f'#{a:02X}{color[1:].upper()}'


def svg(shapes, size, view=None, uid=''):
    """`uid`: aynı belgeye birden çok çizim konunca kimlikler çakışmasın."""
    view = view or (0, 0, size, size)
    defs, body = [], []
    for i, s in enumerate(shapes):
        if isinstance(s.fill, Linear):
            g = s.fill
            stops = ''.join(
                f'<stop offset="{o}" stop-color="{c[:7]}" stop-opacity="{(int(c[7:9], 16) / 255 if len(c) == 9 else 1):.3f}"/>'
                for o, c in g.stops)
            defs.append(f'<linearGradient id="{uid}g{i}" gradientUnits="userSpaceOnUse" x1="{g.p1[0]:.3f}" y1="{g.p1[1]:.3f}" '
                        f'x2="{g.p2[0]:.3f}" y2="{g.p2[1]:.3f}">{stops}</linearGradient>')
            fill = f'url(#{uid}g{i})'
        else:
            fill = s.fill[:7]
        alpha = s.alpha * (int(s.fill[7:9], 16) / 255 if isinstance(s.fill, str) and len(s.fill) == 9 else 1)
        el = f'<path d="{pathdata(s.path)}" fill="{fill}"' + (f' fill-opacity="{alpha:.3f}"' if alpha < 1 else '') + '/>'
        # iç içe kırpmalar kesişir: her kırpma ayrı bir grup
        for j, c in enumerate(reversed(s.clips)):
            defs.append(f'<clipPath id="{uid}c{i}_{j}"><path d="{pathdata(c)}"/></clipPath>')
            el = f'<g clip-path="url(#{uid}c{i}_{j})">{el}</g>'
        body.append(el)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{" ".join(str(v) for v in view)}" '
            f'width="{view[2]}" height="{view[3]}"><defs>{"".join(defs)}</defs>{"".join(body)}</svg>\n')


def vector(shapes, size, dp, comment):
    """Android VectorDrawable. Geçişler `aapt:attr` ile (API 24+; uyarlanabilir simge zaten 26+)."""
    need_aapt = any(isinstance(s.fill, Linear) for s in shapes)
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<!-- tool/simge.py üretti; elle değiştirme. ' + comment + ' -->',
           '<vector xmlns:android="http://schemas.android.com/apk/res/android"'
           + ('\n    xmlns:aapt="http://schemas.android.com/aapt"' if need_aapt else ''),
           f'    android:width="{dp}dp"', f'    android:height="{dp}dp"',
           f'    android:viewportWidth="{size}"', f'    android:viewportHeight="{size}">']

    def path_xml(s, ind):
        pad = ' ' * ind
        lines = [f'{pad}<path', f'{pad}    android:pathData="{pathdata(s.path)}"']
        if isinstance(s.fill, Linear):
            g = s.fill
            lines[-1] += '>'
            lines += [f'{pad}    <aapt:attr name="android:fillColor">',
                      f'{pad}        <gradient',
                      f'{pad}            android:type="linear"',
                      f'{pad}            android:startX="{g.p1[0]:.3f}"',
                      f'{pad}            android:startY="{g.p1[1]:.3f}"',
                      f'{pad}            android:endX="{g.p2[0]:.3f}"',
                      f'{pad}            android:endY="{g.p2[1]:.3f}">']
            for o, c in g.stops:
                lines.append(f'{pad}            <item android:offset="{o}" android:color="{_argb(c, s.alpha)}" />')
            lines += [f'{pad}        </gradient>', f'{pad}    </aapt:attr>', f'{pad}</path>']
        else:
            lines.append(f'{pad}    android:fillColor="{_argb(s.fill, s.alpha)}" />')
        return lines

    for s in shapes:
        ind = 4
        opened = 0
        for c in s.clips:
            out += [' ' * ind + '<group>', ' ' * ind + f'    <clip-path android:pathData="{pathdata(c)}" />']
            ind += 4
            opened += 1
        out += path_xml(s, ind)
        for _ in range(opened):
            ind -= 4
            out.append(' ' * ind + '</group>')
    out.append('</vector>')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- simgenin kendisi
# 108 birimlik uyarlanabilir simge tuvali (Android: 108dp, görünen orta 72dp, kesin güvenli alan
# ortada 66dp çaplı daire). Biçim: kağıt bir kutu, içinden iki kart çıkıyor; öndeki bir fotoğraf
# baskısı ("görsel envanter"), arkadaki uygulamanın kart renklerinden. Kutunun kulpu eski simgedeki
# fiş dolabından kaldı.

GLYPH = scale(1.06, 54, 54)
BOX = (32, 50, 44, 24)
BOX_R = 6.6
BACK = ((36, 31.5, 30, 34), rotate(-8, 51, 64))
FRONT = ((42, 35, 30, 34), rotate(6, 57, 64))
CARD_R = 3.4

# Klasör/kutu üzerindeki ev işareti: çatılı, bacalı ve kemer kapılı ev silueti.
HOUSE_OUTLINE = poly([
    (54.0, 55.0),               # çatı tepe noktası
    (57.8, 57.9),               # sağ çatı eğimi
    (57.8, 55.4),               # baca sol
    (59.4, 55.4),               # baca üst sağ
    (59.4, 59.1),               # baca sağ birleşim
    (60.8, 60.2),               # sağ saçak ucu
    (59.2, 60.2),               # sağ saçak altı
    (59.2, 66.2),               # sağ duvar tabanı
    (48.8, 66.2),               # sol duvar tabanı
    (48.8, 60.2),               # sol saçak altı
    (47.2, 60.2),               # sol saçak ucu
])

HOUSE_DOOR = [
    ('M', (52.4, 66.2)),
    ('L', (52.4, 63.2)),
    _arc((54.0, 63.2), 1.6, 180, 270),
    _arc((54.0, 63.2), 1.6, 270, 360),
    ('L', (55.6, 66.2)),
    ('Z',)
]

HOUSE = HOUSE_OUTLINE + reverse(HOUSE_DOOR)


def _card_shape(rect, m, color):
    x, y, w, h = rect
    path = transform(rrect(x, y, w, h, CARD_R), m)
    # Kartın kendi ekseninde, kutuya girdiği yere doğru koyulaşır: kart kutunun içinde dursun.
    fill = Linear(apply(m, (x, y + h * 0.42)), apply(m, (x, y + h * 0.62)), [(0, color), (1, mix(color, DEEP, 0.22))])
    return Shape(path, fill)


def _photo(rect, m):
    x, y, w, h = rect
    px, py, pw, ph = x + 3.2, y + 3.2, w - 6.4, 12.5
    frame = transform(rrect(px, py, pw, ph, 2.2), m)
    hill = transform(poly([(px - 1, py + ph + 1), (px + pw * 0.34, py + ph * 0.45), (px + pw * 0.58, py + ph * 0.75),
                           (px + pw * 0.72, py + ph * 0.58), (px + pw + 1, py + ph + 1)]), m)
    sun = transform(circle(px + pw * 0.76, py + ph * 0.3, 1.9), m)
    return [Shape(frame, SKY), Shape(hill, HILL, clips=[frame]), Shape(sun, SUN, clips=[frame])]


def foreground():
    shapes = [_card_shape(BACK[0], BACK[1], BLUE), _card_shape(FRONT[0], FRONT[1], PRINT)]
    shapes += _photo(*FRONT)
    box = rrect(*BOX, BOX_R)
    # Kutunun alt kenarında keskin, kısa bir gölge (bulanıklık vektörde yok; düz ofset daha temiz).
    shapes.append(Shape(transform(box, (1, 0, 0, 0, 1, 1.4)), SHADOW, 0.35))
    shapes.append(Shape(box, Linear((0, BOX[1]), (0, BOX[1] + BOX[3]), [(0, BOX_TOP), (1, BOX_BOTTOM)])))
    shapes.append(Shape(HOUSE, HANDLE))
    return moved(shapes, GLYPH)


def background():
    return [Shape(rrect(0, 0, 108, 108, 0), Linear((0, 0), (0, 108), [(0, BG_TOP), (1, BG_BOTTOM)]))]


def _outside(path, pad=200):
    """`path`'in dışındaki her yer (kırpma yolu olarak): büyük dikdörtgen + ters yönlü delik."""
    return rrect(-pad, -pad, 108 + 2 * pad, 108 + 2 * pad, 0) + reverse(path)


def silhouette(gap, photo=True, color='#FFFFFF'):
    """Tek renkli biçim: tema simgesi ve bildirim simgesi. Renk yok, katmanlar ancak aralarındaki
    boşlukla ayrılır: öndeki her parça arkasındakinden `gap` kadar oyulur."""
    bx, by, bw, bh = BOX
    box = rrect(*BOX, BOX_R)
    box_cut = rrect(bx - gap, by - gap, bw + 2 * gap, bh + 2 * gap, BOX_R + gap)
    (fx, fy, fw, fh), fm = FRONT
    front = transform(rrect(fx, fy, fw, fh, CARD_R), fm)
    front_cut = transform(rrect(fx - gap, fy - gap, fw + 2 * gap, fh + 2 * gap, CARD_R + gap), fm)
    (kx, ky, kw, kh), km = BACK
    back = transform(rrect(kx, ky, kw, kh, CARD_R), km)
    shapes = [Shape(back, color, clips=[_outside(box_cut), _outside(front_cut)])]
    if photo:
        # Baskının fotoğraf alanı delik, içinde tepe: tema simgesinde de "fotoğraf" okunsun.
        px, py, pw, ph = fx + 3.2, fy + 3.2, fw - 6.4, 12.5
        window = transform(rrect(px, py, pw, ph, 2.2), fm)
        shapes.append(Shape(front + reverse(window), color, clips=[_outside(box_cut)]))
        hill = transform(poly([(px - 1, py + ph + 1), (px + pw * 0.34, py + ph * 0.45), (px + pw * 0.58, py + ph * 0.75),
                               (px + pw * 0.72, py + ph * 0.58), (px + pw + 1, py + ph + 1)]), fm)
        shapes.append(Shape(hill, color, clips=[window, _outside(box_cut)]))
    else:
        shapes.append(Shape(front, color, clips=[_outside(box_cut)]))
    shapes.append(Shape(box + reverse(HOUSE_OUTLINE) + HOUSE_DOOR, color))
    return moved(shapes, GLYPH)


def fitted(shapes, size, margin):
    """Biçimi `size` birimlik tuvale ortalar (bildirim simgesi 24, açılış simgesi kendi kutusu)."""
    xs, ys = [], []
    for s in shapes:
        x0, y0, x1, y1 = bounds(s.path)
        xs += [x0, x1]
        ys += [y0, y1]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    k = (size - 2 * margin) / max(w, h)
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    return then((1, 0, -cx, 0, 1, -cy), (k, 0, size / 2, 0, k, size / 2))


def launcher_tile(size=108):
    """Uyarlanabilir simgenin görünen orta 72 birimi, yumuşak köşeli kare içinde (Android 7 simgesi
    ve 12 öncesi açılış ekranı için). `size` birimlik tuvalde, gölgesiz."""
    tile = rrect(0, 0, size, size, size * 0.225)
    k = size / 72
    m = then((1, 0, -18, 0, 1, -18), (k, 0, 0, 0, k, 0))
    bg = Shape(tile, Linear((0, 0), (0, size), [(0, BG_TOP), (1, BG_BOTTOM)]))
    return [bg] + [s.moved(m) for s in foreground()]


# ---------------------------------------------------------------- yazma

def write(rel, text):
    path = os.path.join(RES, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    print('  ' + os.path.relpath(path, ROOT))


def render(svg_text, out, px):
    src = out[:-4] + '.svg'
    with open(src, 'w') as f:
        f.write(svg_text)
    subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), src, '-o', out], check=True)


def preview_sheet():
    """Bütün kullanımlar tek sayfada: başlatıcı maskeleri (daire, yumuşak kare, yuvarlak kare) açık
    ve koyu duvar kâğıdında, küçük boylar, tema simgesi (açık/koyu), bildirim çubuğu, açılış ekranı."""
    icon = background() + foreground()
    mono = silhouette(gap=1.6)
    stat = silhouette(gap=2.4, photo=False)
    stat = moved(stat, fitted(stat, 24, 1))
    tiles, y = [], 0

    def place(shapes, view, x, y, w, clip=None, under=None):
        cid = f'm{len(tiles)}'
        inner = svg(shapes, view[2], view, uid=cid).split('>', 1)[1].rsplit('</svg>', 1)[0]
        clip_el = ''
        if clip is not None:
            clip_el = f'<clipPath id="{cid}"><path d="{pathdata(clip)}"/></clipPath>'
        body = f'<svg x="{x}" y="{y}" width="{w}" height="{w}" viewBox="{" ".join(str(v) for v in view)}">' + clip_el
        if under:
            body += f'<path d="{pathdata(rrect(*view, 0))}" fill="{under}"' + (f' clip-path="url(#{cid})"' if clip else '') + '/>'
        body += (f'<g clip-path="url(#{cid})">' if clip else '<g>') + inner + '</g></svg>'
        tiles.append(body)

    masks = [circle(54, 54, 36), rrect(18, 18, 72, 72, 26, 0.6), rrect(18, 18, 72, 72, 16, 0)]
    for row, (wall, label) in enumerate((('#EEE9E1', 'açık'), ('#1B1D22', 'koyu'))):
        tiles.append(f'<rect x="0" y="{y}" width="980" height="236" fill="{wall}"/>')
        for i, m in enumerate(masks):
            place(icon, (18, 18, 72, 72), 24 + i * 200, y + 24, 176, clip=m)
        for j, px in enumerate((72, 48, 36, 24)):
            place(icon, (18, 18, 72, 72), 640 + sum((72, 48, 36, 24)[:j]) + j * 20, y + 118 - px // 2, px, clip=masks[0])
        y += 236
    # tema simgesi: sistem tek renkli katmanı kendi renkleriyle boyar
    tiles.append(f'<rect x="0" y="{y}" width="980" height="236" fill="#EEE9E1"/>')
    for i, (bgc, fg) in enumerate((('#F2DDD3', '#3B1F15'), ('#3A2A24', '#F4D8CC'))):
        tinted = [Shape(s.path, fg, s.alpha, s.clips) for s in mono]
        place(tinted, (18, 18, 72, 72), 24 + i * 200, y + 24, 176, clip=masks[0], under=bgc)
    # bildirim çubuğu
    tiles.append(f'<rect x="440" y="{y + 60}" width="500" height="116" rx="18" fill="#1F2125"/>')
    white = [Shape(s.path, '#FFFFFF', s.alpha, s.clips) for s in stat]
    place(white, (0, 0, 24, 24), 470, y + 94, 48)
    place(white, (0, 0, 24, 24), 540, y + 106, 24)
    tiles.append(f'<rect x="590" y="{y + 100}" width="300" height="12" rx="6" fill="#55585F"/>'
                 f'<rect x="590" y="{y + 124}" width="210" height="10" rx="5" fill="#3D4046"/>')
    y += 236
    # açılış ekranı (Android 12+: sistem simgeyi daire içinde gösterir; 12 öncesi ic_splash)
    for i, (paper, label) in enumerate((('#F2EDE4', 'açık'), ('#14120F', 'koyu'))):
        tiles.append(f'<rect x="{24 + i * 240}" y="{y + 16}" width="210" height="380" rx="26" fill="{paper}"/>')
        place(icon, (18, 18, 72, 72), 24 + i * 240 + 45, y + 146, 120, clip=masks[0])
    place(launcher_tile(), (0, 0, 108, 108), 560, y + 146, 120)
    tiles.append(f'<rect x="520" y="{y + 16}" width="210" height="380" rx="26" fill="none" stroke="#CFC6B8" stroke-width="2"/>')
    y += 420
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 980 {y}" width="980" height="{y}">'
            f'<rect width="980" height="{y}" fill="#EEE9E1"/>{"".join(tiles)}</svg>\n')


def main():
    os.makedirs(PREVIEW, exist_ok=True)
    print('Android kaynakları:')
    write('drawable/ic_launcher_background.xml',
          vector(background(), 108, 108, 'Uyarlanabilir simgenin zemini.'))
    write('drawable/ic_launcher_foreground.xml',
          vector(foreground(), 108, 108, 'Uyarlanabilir simgenin ön planı: kutu ve kartlar.'))
    write('drawable/ic_launcher_monochrome.xml',
          vector(silhouette(gap=1.6), 108, 108, 'Android 13+ tema simgesi: sistem tek renge boyar.'))
    stat = silhouette(gap=2.4, photo=False)
    write('drawable/ic_stat_envanter.xml',
          vector(moved(stat, fitted(stat, 24, 1)), 24, 24, 'Bildirim simgesi: tek renk, Android boyar.'))
    write('drawable/ic_splash.xml',
          vector(launcher_tile(), 108, 112, 'Android 12 öncesi açılış ekranındaki simge.'))
    # Android 7 (API 24–25) uyarlanabilir simgeyi bilmez: düz PNG, gölgesi ince.
    for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        k = px / 48
        tile = [s.moved((k * 44 / 108, 0, 2 * k, 0, k * 44 / 108, 1.5 * k)) for s in launcher_tile()]
        shadow = Shape(rrect(2 * k, 2.5 * k, 44 * k, 44 * k, 44 * k * 0.225), '#000000', 0.18)
        out = os.path.join(RES, f'mipmap-{folder}', 'ic_launcher.png')
        src = os.path.join(PREVIEW, f'legacy_{folder}.svg')
        with open(src, 'w') as f:
            f.write(svg([shadow] + tile, px))
        subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), src, '-o', out], check=True)
        print('  ' + os.path.relpath(out, ROOT))
    # Önizlemeler: tam katmanlar (432 px = 108 birim × 4).
    render(svg(background() + foreground(), 108), os.path.join(PREVIEW, 'tam.png'), 432)
    render(svg([Shape(rrect(0, 0, 108, 108, 0), '#30343C')] + silhouette(gap=1.6), 108),
           os.path.join(PREVIEW, 'tek_renk.png'), 432)
    render(svg([Shape(rrect(0, 0, 24, 24, 0), '#30343C')] + moved(stat, fitted(stat, 24, 1)), 24),
           os.path.join(PREVIEW, 'bildirim.png'), 96)
    render(svg(launcher_tile(), 108), os.path.join(PREVIEW, 'acilis.png'), 336)
    sheet = os.path.join(PREVIEW, 'onizleme.svg')
    with open(sheet, 'w') as f:
        f.write(preview_sheet())
    subprocess.run(['rsvg-convert', sheet, '-o', sheet[:-4] + '.png'], check=True)
    print('Önizlemeler: ' + os.path.relpath(PREVIEW, ROOT) + '/')


if __name__ == '__main__':
    sys.exit(main())
