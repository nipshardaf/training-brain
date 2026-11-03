"""Draw the exercise pictures that free-exercise-db has no photo for (gym-sign style).

Run from the repo root:  python3 assets/ex/draw.py
Writes assets/ex/<id>.svg (start) and assets/ex/<id>-2.svg (end of the movement); the app's
"Animate" button flips between the two. A figure faces right and is built from joint angles in
degrees (0 = forward/right, 90 = down, -90 = up). The working muscle is drawn in orange.
Better pictures (photos or AI images) can replace these later: see README.md here.
"""
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))
W, H, FL = 900, 500, 452  # canvas and floor line
C = dict(bg='#f3f1fb', floor='#dcd7f3', body='#2f3442', far='#aab0be', hi='#f97316',
         frame='#a5acb9', pad='#7c3aed', cable='#64748b', metal='#4b5563', cloth='#c7d2fe')
L = dict(torso=118, neck=16, head=23, ua=78, fa=72, th=104, sh=100, ft=34)
WD = dict(torso=40, ua=24, fa=20, th=32, sh=24, ft=16)


def P(p, a, l):
    r = math.radians(a)
    return (p[0] + l * math.cos(r), p[1] + l * math.sin(r))


def ln(a, b, w, c, cap='round', op=1):
    return (f'<line x1="{a[0]:.0f}" y1="{a[1]:.0f}" x2="{b[0]:.0f}" y2="{b[1]:.0f}" stroke="{c}" '
            f'stroke-width="{w}" stroke-linecap="{cap}" opacity="{op}"/>')


def ci(p, r, c, op=1):
    return f'<circle cx="{p[0]:.0f}" cy="{p[1]:.0f}" r="{r}" fill="{c}" opacity="{op}"/>'


def rc(x, y, w, h, c, rx=8):
    return f'<rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" rx="{rx}" fill="{c}"/>'


def path(d, c, w=0, fill='none', op=1):
    if w:
        return f'<path d="{d}" stroke="{c}" stroke-width="{w}" fill="{fill}" stroke-linecap="round" stroke-linejoin="round" opacity="{op}"/>'
    return f'<path d="{d}" fill="{c}" opacity="{op}"/>'


def pad_along(a, b, off, w, c=None, extend=0):
    """A pad (thick line) parallel to segment a-b, shifted sideways by off px."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1
    nx, ny = -dy / n * off, dx / n * off
    ex, ey = dx / n * extend, dy / n * extend
    return ln((a[0] + nx - ex, a[1] + ny - ey), (b[0] + nx + ex, b[1] + ny + ey), w, c or C['pad'])


def figure(hip=None, ankle=None, torso=-90, ua=90, fa=90, th=90, sh=90, ft=0, hi=(), far=None, ual=1.0):
    """Joint points and SVG for one figure. With ankle=, sh and th are the angles going UP the
    leg (ankle to knee, knee to hip), for planted feet; otherwise they go down from the hip."""
    j = {}
    if ankle is not None:
        j['ank'] = ankle; j['kne'] = P(ankle, sh, L['sh']); j['hip'] = P(j['kne'], th, L['th'])
        th_d, sh_d = (th + 180) % 360, (sh + 180) % 360
    else:
        j['hip'] = hip; j['kne'] = P(hip, th, L['th']); j['ank'] = P(j['kne'], sh, L['sh'])
        th_d, sh_d = th, sh
    j['toe'] = P(j['ank'], ft, L['ft'])
    j['sho'] = P(j['hip'], torso, L['torso'])
    j['nek'] = P(j['sho'], torso, L['neck'])
    j['hed'] = P(j['nek'], torso, L['head'])
    j['elb'] = P(j['sho'], ua, L['ua'] * ual)
    j['wri'] = P(j['elb'], fa, L['fa'] * ual)
    s = []
    if far:  # the limbs on the far side, lighter, behind everything
        fk = P(j['hip'], far.get('th', th_d), L['th']); fa_ = P(fk, far.get('sh', sh_d), L['sh'])
        s += [ln(j['hip'], fk, WD['th'], C['far']), ln(fk, fa_, WD['sh'], C['far']),
              ln(fa_, P(fa_, far.get('ft', ft), L['ft']), WD['ft'], C['far'])]
        if 'ua' in far:
            fe = P(j['sho'], far['ua'], L['ua']); fw = P(fe, far.get('fa', far['ua']), L['fa'])
            s += [ln(j['sho'], fe, WD['ua'], C['far']), ln(fe, fw, WD['fa'], C['far'])]
    seg = dict(torso=(j['hip'], j['sho']), th=(j['hip'], j['kne']), sh=(j['kne'], j['ank']),
               ft=(j['ank'], j['toe']), ua=(j['sho'], j['elb']), fa=(j['elb'], j['wri']))
    for k in ('torso', 'th', 'sh', 'ft'):
        s.append(ln(*seg[k], WD[k], C['hi'] if k in hi else C['body']))
    s += highlights(j, hi, torso, th_d, sh_d)
    s.append(ln(j['sho'], j['nek'], 16, C['body']))
    s.append(ci(j['hed'], L['head'], C['body']))
    for k in ('ua', 'fa'):
        s.append(ln(*seg[k], WD[k], C['hi'] if k in hi else C['body']))
    if 'delt' in hi:
        s.append(ci(j['sho'], 15, C['hi']))
    return j, ''.join(s)


def highlights(j, hi, torso, th, sh):
    """Orange stripes on the front or back half of a segment (chest, back, abs, quads...)."""
    out = []

    def stripe(a, b, side, frac0, frac1, w=14, off=11):
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1
        nx, ny = -dy / n * off * side, dx / n * off * side
        p0 = (a[0] + dx * frac0 + nx, a[1] + dy * frac0 + ny)
        p1 = (a[0] + dx * frac1 + nx, a[1] + dy * frac1 + ny)
        out.append(ln(p0, p1, w, C['hi']))
    # torso: +1 = front (chest, abs) for a figure facing right
    if 'chest' in hi: stripe(j['hip'], j['sho'], 1, .55, .95)
    if 'abs' in hi: stripe(j['hip'], j['sho'], 1, .1, .55)
    if 'lats' in hi: stripe(j['hip'], j['sho'], -1, .4, .95)
    if 'lowback' in hi: stripe(j['hip'], j['sho'], -1, .05, .5)
    if 'oblique' in hi: stripe(j['hip'], j['sho'], 1, .15, .6, w=12, off=4)
    # legs: going down from the hip the front is the other side
    if 'quad' in hi: stripe(j['hip'], j['kne'], -1, .1, .9, w=13, off=8)
    if 'ham' in hi: stripe(j['hip'], j['kne'], 1, .1, .9, w=13, off=8)
    if 'calf' in hi: stripe(j['kne'], j['ank'], 1, .1, .6, w=12, off=6)
    if 'glute' in hi:
        dx, dy = j['sho'][0] - j['hip'][0], j['sho'][1] - j['hip'][1]
        n = math.hypot(dx, dy) or 1
        out.append(ci((j['hip'][0] + dy / n * 12, j['hip'][1] - dx / n * 12), 17, C['hi']))
    return out


def svg(parts, floor=True):
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
         rc(0, 0, W, H, C['bg'], 0)]
    if floor:
        s.append(rc(0, FL, W, H - FL, C['floor'], 0))
    s += parts
    s.append('</svg>')
    return ''.join(s)


def save(eid, frames):
    for i, f in enumerate(frames):
        name = f'{eid}.svg' if i == 0 else f'{eid}-{i + 1}.svg'
        with open(os.path.join(OUT, name), 'w') as fh:
            fh.write(f)


def arrow_arc(cx, cy, r, a0, a1, c=None):
    c = c or C['hi']
    p0, p1 = P((cx, cy), a0, r), P((cx, cy), a1, r)
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    tip = P(p1, a1 + (90 if sweep else -90), 0)
    head_a = a1 + (90 if sweep else -90)
    h1, h2 = P(p1, head_a + 150, 22), P(p1, head_a - 150, 22)
    return (path(f'M{p0[0]:.0f} {p0[1]:.0f} A{r} {r} 0 {large} {sweep} {p1[0]:.0f} {p1[1]:.0f}', c, 10) +
            path(f'M{h1[0]:.0f} {h1[1]:.0f} L{tip[0]:.0f} {tip[1]:.0f} L{h2[0]:.0f} {h2[1]:.0f}', c, 10))


# ── scenes ───────────────────────────────────────────────────────────────────────────────────
def bench_back(x0=210, x1=360, y=318):
    return rc(x0, y, x1 - x0, 26, C['pad'], 10) + ln((x0 + 25, y + 26), (x0 + 25, FL), 12, C['frame']) + \
        ln((x1 - 25, y + 26), (x1 - 25, FL), 12, C['frame'])


def hip_thrust(eid, smith=False):
    frames = []
    for up in (False, True):
        hip = (480, 320) if up else (472, 392)
        j, fig = figure(hip=hip, torso=-176 if up else -150, th=14 if up else -22, sh=88 if up else 74, ft=0,
                        ua=40 if up else 55, fa=0, hi=('glute', 'ham'))
        parts = [bench_back()]
        if smith:
            parts += [ln((hip[0], 40), (hip[0], FL), 10, C['frame']), ln((hip[0] + 14, 40), (hip[0] + 14, FL), 6, C['frame'])]
        parts.append(fig)
        if smith:
            parts += [ci((hip[0] + 6, hip[1] - 26), 15, C['metal']), ci((hip[0] + 6, hip[1] - 26), 46, C['metal'], .35)]
        else:
            parts += [pad_along((hip[0] - 40, hip[1] - 28), (hip[0] + 40, hip[1] - 28), 0, 22),
                      ln((hip[0] + 40, hip[1] - 28), (640, 120), 10, C['frame']), ci((640, 120), 34, C['metal'], .5)]
        frames.append(svg(parts))
    save(eid, frames)


def squat_machine(eid, kind):
    frames = []
    for down in (False, True):
        ank = (470, 420)
        if kind == 'pendulum':
            sh_up, th_up, torso = (-58, -172, -84) if down else (-92, -92, -96)
        elif kind == 'v':
            sh_up, th_up, torso = (-60, -168, -70) if down else (-88, -95, -84)
        else:  # belt squat
            sh_up, th_up, torso = (-62, -170, -78) if down else (-90, -90, -88)
        j, fig = figure(ankle=ank, sh=sh_up, th=th_up, torso=torso, ft=0,
                        ua=8 if kind == 'belt' else 150, fa=-30 if kind == 'belt' else -60, hi=('quad', 'glute'))
        parts = [rc(395, 420, 170, 18, C['metal'], 5)]  # platform
        if kind == 'pendulum':
            pv = (210, 70)
            parts += [ln(pv, j['sho'], 12, C['frame']), pad_along(j['hip'], j['sho'], -28, 20, extend=10),
                      ci(pv, 16, C['metal'])]
        if kind == 'v':
            pv = (230, 330)
            parts += [ln(pv, P(j['sho'], 180, 30), 12, C['frame']), ci(pv, 16, C['metal']),
                      ci(P(pv, 200, 60), 34, C['metal'], .5)]
        if kind == 'belt':
            parts += [rc(612, 220, 14, 232, C['frame'], 6), ln((470, 438), (470, FL), 8, C['frame'])]
        parts.append(fig)
        if kind in ('pendulum', 'v'):
            parts.append(ci(P(j['sho'], 0, 2), 16, C['pad']))
        if kind == 'belt':
            parts += [ln(j['hip'], (j['hip'][0], 436), 6, C['cable']), pad_along((j['hip'][0] - 22, j['hip'][1]), (j['hip'][0] + 22, j['hip'][1]), 0, 14)]
        frames.append(svg(parts))
    save(eid, frames)


def seated_leg_press():
    frames = []
    for out in (False, True):
        hip = (330, 330) if out else (400, 330)
        j, fig = figure(hip=hip, torso=-122, th=-5 if out else -25, sh=-4 if out else 58, ft=-90,
                        ua=70, fa=10, hi=('quad', 'glute'))
        parts = [rc(hip[0] - 50, hip[1] + 14, 130, 22, C['pad'], 10), pad_along(j['hip'], j['sho'], -26, 20, extend=12),
                 ln((hip[0] - 20, hip[1] + 36), (hip[0] - 20, FL), 12, C['frame']), ln((hip[0] + 60, hip[1] + 36), (hip[0] + 60, FL), 12, C['frame']),
                 rc(560, 220, 22, 200, C['pad'], 10), ln((582, 330), (680, 330), 12, C['frame']), ci((700, 330), 40, C['metal'], .5), fig]
        frames.append(svg(parts))
    save('seated_leg_press', frames)


def sl_leg_press():
    frames = []
    for out in (False, True):
        hip = (360, 372)
        j, fig = figure(hip=hip, torso=-160, th=-42 if out else -62, sh=-40 if out else 8, ft=-130,
                        ua=40, fa=20, hi=('quad', 'glute'), far=dict(th=20, sh=110, ft=0))
        a = j['ank']
        p0, p1 = P(a, 50, 66), P(a, 230, 66)
        parts = [ln((300, 430), (820, 60), 14, C['frame']), pad_along((200, 352), (360, 400), 0, 26),
                 ln((250, 390), (250, FL), 12, C['frame']), fig, ln(p0, p1, 18, C['pad'])]
        frames.append(svg(parts))
    save('sl_leg_press', frames)


def glute_kick():
    frames = []
    for back in (False, True):
        hip = (450, 300)
        j, fig = figure(hip=hip, torso=-12, ua=88, fa=10, th=150 if back else 82, sh=176 if back else 140,
                        ft=-90 if back else 160, hi=('glute', 'ham'), far=dict(th=92, sh=90, ft=0))
        a = j['ank']
        parts = [pad_along(P(j['hip'], -12, 50), P(j['sho'], -12, 10), 26, 24), rc(560, 330, 14, 122, C['frame'], 6),
                 rc(380, 432, 160, 16, C['metal'], 5), fig, ln((a[0] - 8, a[1] - 46), (a[0] - 8, a[1] + 36), 14, C['pad']),
                 ln((a[0] - 8, a[1]), (330, 250), 8, C['frame'])]
        frames.append(svg(parts))
    save('glute_kick_mach', frames)


def landmine():
    frames = []
    for up in (False, True):
        j, fig = figure(ankle=(470, 440), sh=-92, th=-90, torso=-84, ft=0, ua=-48 if up else 100, fa=-52 if up else -84,
                        hi=('delt', 'chest') if up else ('delt',), far=dict(th=110, sh=95, ft=0))
        w = j['wri']
        piv = (190, 440)
        end = P(w, math.degrees(math.atan2(w[1] - piv[1], w[0] - piv[0])), 40)
        parts = [ci(piv, 12, C['metal']), ln(piv, end, 12, C['metal']), fig, ci(end, 30, C['metal'], .6)]
        frames.append(svg(parts))
    save('landmine_press', frames)


def cable_scene(eid, start, end, pulley, hi):
    frames = []
    for pose in (start, end):
        j, fig = figure(ankle=(430, 440), sh=-90, th=-90, torso=pose.get('torso', -90), ft=0, ua=pose['ua'], fa=pose['fa'],
                        hi=hi, far=pose.get('far'))
        tower_x = pulley[0]
        parts = [rc(tower_x - 12 if tower_x > 450 else tower_x - 2, 40, 14, 412, C['frame'], 6), ci(pulley, 13, C['metal']),
                 ln(j['wri'], pulley, 4, C['cable']), fig, ci(j['wri'], 9, C['metal'])]
        frames.append(svg(parts))
    save(eid, frames)


def seated_frame(hip, back=True):
    s = [rc(hip[0] - 55, hip[1] + 14, 120, 22, C['pad'], 10), ln((hip[0], hip[1] + 36), (hip[0], FL), 14, C['frame'])]
    return ''.join(s)


def iso_pulldown():
    frames = []
    for down in (False, True):
        hip = (420, 330)
        j, fig = figure(hip=hip, torso=-95, th=0, sh=90, ft=0, ua=104 if down else -84, fa=-66 if down else -88, hi=('lats',))
        piv = (250, 70)
        parts = [seated_frame(hip), rc(505, 280, 50, 22, C['pad'], 10), ln(j['wri'], piv, 12, C['frame']),
                 ci(piv, 16, C['metal']), ci(P(piv, 200, 70), 34, C['metal'], .5), fig, ci(j['wri'], 10, C['metal'])]
        frames.append(svg(parts))
    save('iso_pulldown', frames)


def pullover():
    frames = []
    for down in (False, True):
        hip = (420, 330)
        j, fig = figure(hip=hip, torso=-92, th=0, sh=90, ft=0, ua=62 if down else -104, fa=20 if down else -100, hi=('lats',))
        parts = [seated_frame(hip), ci(P(j['sho'], 180, 4), 52, C['frame'], .45), fig,
                 pad_along(j['sho'], j['elb'], 0, 16, extend=-30), ci(j['elb'], 14, C['pad'])]
        frames.append(svg(parts))
    save('mach_pullover', frames)


def back_ext_mach():
    frames = []
    for up in (False, True):
        hip = (430, 330)
        j, fig = figure(hip=hip, torso=-98 if up else -52, th=0, sh=90, ft=0, ua=55 if up else 80, fa=-150 if up else -110,
                        hi=('lowback', 'glute'))
        parts = [seated_frame(hip), pad_along(P(j['hip'], -98 if up else -52, 80), j['sho'], -30, 22, extend=8),
                 ln((j['sho'][0] - 40, j['sho'][1]), (300, 120), 10, C['frame']), rc(520, 420, 60, 16, C['metal'], 5), fig]
        frames.append(svg(parts))
    save('back_ext_mach', frames)


def rotary():
    frames = []
    for i, d in enumerate((1, -1)):
        hip = (440, 330)
        j, fig = figure(hip=hip, torso=-90, th=0, sh=90, ft=0, ua=0, fa=0, ual=.55 if i else 1.0, hi=('oblique',))
        parts = [seated_frame(hip), fig, arrow_arc(j['sho'][0], j['sho'][1] + 40, 92, 200 if d > 0 else -20, 340 if d > 0 else -160)]
        frames.append(svg(parts))
    save('rotary_torso', frames)


def wall_sit():
    hip = (372, 330)
    j, fig = figure(hip=hip, torso=-90, th=0, sh=90, ft=0, ua=58, fa=-2, hi=('quad',))
    save('wall_sit', [svg([rc(300, 60, 46, 392, C['frame'], 4), fig])])


def foot(arch=30, toes='flat', heel_up=0, shin=True, towel=None, hi_arch=False, hi_calf=False):
    """A big side view of a foot and lower leg (feet exercises)."""
    hx, fy = 300, 420                      # heel, floor
    lift = heel_up
    ball = (560, fy) if not lift else (560, fy)
    heel = (hx + lift * .2, fy - lift)
    ank = (heel[0] + 40, heel[1] - 110)
    s = []
    if towel:
        s.append(path(towel, C['cloth']))
    if shin:
        knee = (ank[0] - 6 + lift * .3, 120)
        s.append(ln(ank, knee, 46, C['body']))
        if hi_calf:
            s.append(ln((ank[0] - 14, ank[1] - 30), (knee[0] - 14, knee[1] + 40), 16, C['hi']))
    tx = ball[0] + 70
    toe_y = fy - (14 if toes == 'curl' else 0)
    d = (f'M{heel[0]:.0f} {heel[1]:.0f} C{heel[0] - 30:.0f} {heel[1] - 40:.0f} {ank[0] - 40:.0f} {ank[1] + 30:.0f} {ank[0] - 30:.0f} {ank[1]:.0f} '
         f'L{ank[0] + 34:.0f} {ank[1]:.0f} C{ank[0] + 60:.0f} {ank[1] + 60:.0f} {ball[0] - 40:.0f} {ball[1] - 70:.0f} {tx:.0f} {toe_y - 26:.0f} '
         f'C{tx + 26:.0f} {toe_y - 20:.0f} {tx + 26:.0f} {toe_y:.0f} {tx:.0f} {toe_y:.0f} '
         f'L{ball[0]:.0f} {ball[1]:.0f} C{ball[0] - 60:.0f} {fy - arch:.0f} {heel[0] + 90:.0f} {fy - arch:.0f} {heel[0] + 40:.0f} {heel[1]:.0f} Z')
    s.append(path(d, C['body']))
    if hi_arch:
        s.append(path(f'M{ball[0] - 20:.0f} {ball[1] - 8:.0f} C{ball[0] - 70:.0f} {fy - arch - 14:.0f} {heel[0] + 90:.0f} {fy - arch - 14:.0f} {heel[0] + 50:.0f} {heel[1] - 8:.0f}',
                      C['hi'], 16))
    return svg(s)


def foot_top(spread):
    """Top view of a foot with the toes together or spread."""
    s = [path('M330 440 C300 330 330 210 420 170 C500 140 590 170 610 240 C630 310 600 380 560 440 Z', C['body'])]
    base = [(452, 182), (500, 170), (540, 180), (572, 200), (596, 228)]
    for i, (x, y) in enumerate(base):
        ang = -100 + i * (22 if spread else 12)
        tip = P((x, y), ang, 46 - i * 5)
        s.append(ln((x, y), tip, 30 - i * 3, C['hi'] if spread else C['body']))
    return svg(s, floor=False)


def make_all():
    hip_thrust('mach_hip_thrust')
    hip_thrust('smith_hip_thrust', smith=True)
    squat_machine('pendulum_squat', 'pendulum')
    squat_machine('v_squat', 'v')
    squat_machine('belt_squat', 'belt')
    seated_leg_press()
    sl_leg_press()
    glute_kick()
    landmine()
    cable_scene('cable_upright_row', dict(ua=86, fa=88), dict(ua=-6, fa=-140), (690, 428), ('delt',))
    cable_scene('cable_y_raise', dict(ua=84, fa=84), dict(ua=-58, fa=-60), (690, 428), ('delt',))
    cable_scene('bayesian_curl', dict(ua=104, fa=112, far=dict(th=110, sh=96, ft=0)),
                dict(ua=104, fa=-62, far=dict(th=110, sh=96, ft=0)), (190, 330), ('ua',))
    iso_pulldown()
    pullover()
    back_ext_mach()
    rotary()
    wall_sit()
    save('short_foot', [foot(arch=28, shin=False), foot(arch=58, shin=False, hi_arch=True)])
    save('arch_raise', [foot(arch=28), foot(arch=60, hi_arch=True)])
    save('heel_raise', [foot(arch=34), foot(arch=46, heel_up=70, hi_calf=True, hi_arch=True)])
    flat = 'M240 440 L760 440 L760 452 L240 452 Z'
    bunch = 'M240 440 L560 440 C600 400 640 400 660 440 C690 410 720 420 760 440 L760 452 L240 452 Z'
    save('towel_scrunch', [foot(arch=30, shin=False, towel=flat), foot(arch=34, toes='curl', shin=False, towel=bunch, hi_arch=True)])
    save('toe_spread', [foot_top(False), foot_top(True)])


if __name__ == '__main__':
    make_all()
    print('done:', len([f for f in os.listdir(OUT) if f.endswith('.svg')]), 'svg files in', OUT)
