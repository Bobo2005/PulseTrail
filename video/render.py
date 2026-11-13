import os
import sys
import math
import wave
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Paths
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOGO_PATH = os.path.join(ROOT_DIR, "frontend", "src", "assets", "logo.png")
SCRATCH_DIR = r"C:\Users\USER\.gemini\antigravity\brain\e25cbfff-71e1-4b1c-bc88-dc58095414c0\scratch"
os.makedirs(SCRATCH_DIR, exist_ok=True)

FPS = 30
DURATION_SEC = 156.0  # Exact 2 minutes 36 seconds (under 3 minutes)
TOTAL_FRAMES = int(FPS * DURATION_SEC)  # 4,680 frames (78 bars @ 120 BPM)

# Brand Palette (from frontend/src/styles.css & reference video)
STAGE_BG = (14, 13, 10)
PAPER_BG = (250, 250, 248)
CARD_BG = (255, 255, 255)
INK = (17, 17, 17)
MUTED = (85, 85, 85)
DOT_COL = (226, 225, 219)
RED = (224, 36, 36)
GREEN = (5, 150, 105)
NEON_GREEN = (0, 245, 155)
PURPLE = (106, 61, 240)
AMBER = (245, 158, 11)
BLUE_NOTE = (29, 78, 216)
BROWSER_BAR = (24, 24, 21)

# Font loader with caching
_FONT_CACHE = {}
def get_font(kind="sans", size=20):
    key = (kind, int(size))
    if key in _FONT_CACHE:
        return _FONT_CACHE[key]
    font_map = {
        "display": ["C:/Windows/Fonts/ariblk.ttf", "C:/Windows/Fonts/segoeuib.ttf"],
        "bold": ["C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"],
        "sans": ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"],
        "mono": ["C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/cour.ttf"],
        "mono_bold": ["C:/Windows/Fonts/consolab.ttf", "C:/Windows/Fonts/courbd.ttf"],
        "script": ["C:/Windows/Fonts/segoesc.ttf", "C:/Windows/Fonts/Inkfree.ttf", "C:/Windows/Fonts/segoeuii.ttf"],
    }
    for p in font_map.get(kind, font_map["sans"]):
        if os.path.exists(p):
            f = ImageFont.truetype(p, int(size))
            _FONT_CACHE[key] = f
            return f
    f = ImageFont.load_default()
    _FONT_CACHE[key] = f
    return f

def get_logo(size=40):
    key = ("logo", size)
    if key in _FONT_CACHE:
        return _FONT_CACHE[key]
    if os.path.exists(LOGO_PATH):
        img = Image.open(LOGO_PATH).convert("RGBA")
        h = int(size * 33 / 32)
        img = img.resize((size, h), Image.NEAREST)
    else:
        img = Image.new("RGBA", (size, size), (0, 245, 155, 255))
    _FONT_CACHE[key] = img
    return img

# ==============================================================================
# VECTOR ICON HELPERS (Zero missing Unicode glyph boxes!)
# ==============================================================================
def draw_check_icon(draw, cx, cy, size=12, color=INK, width=3):
    r = size // 2
    pts = [
        (cx - r, cy),
        (cx - r // 4, cy + int(r * 0.75)),
        (cx + r + 1, cy - int(r * 0.65)),
    ]
    draw.line(pts, fill=color, width=width, joint="curve")

def draw_lock_icon(draw, x, y, color=(180, 178, 170)):
    draw.arc((x + 2, y, x + 10, y + 8), start=180, end=0, fill=color, width=2)
    draw.rounded_rectangle((x, y + 6, x + 12, y + 15), radius=2, fill=color)

# Exact simulation path & state machine from frontend/src/lib/sim.js
K_POINTS = [[0, 1.0], [10, 1.08], [20, 1.35], [45, 2.0], [55, 1.75], [65, 1.55], [79, 1.25]]
SIM_PATH = []
for t in range(80):
    val = 1.0
    for k in range(len(K_POINTS) - 1):
        t0, v0 = K_POINTS[k]
        t1, v1 = K_POINTS[k + 1]
        if t0 <= t <= t1:
            f = (t - t0) / float(t1 - t0)
            val = v0 + (v1 - v0) * f + 0.03 * math.sin(t * 1.7)
            break
    SIM_PATH.append(val)

PORTIONS = [0.40, 0.30, 0.30]
DEMO_USD = 1000.0

def sim_vol(idx):
    s, n = 0.0, 0
    for k in range(max(1, idx - 7), idx + 1):
        c = abs(SIM_PATH[k] / SIM_PATH[k - 1] - 1.0)
        if c >= 0.0005:
            s += c
            n += 1
    return (s / n) if n > 0 else 0.0

def run_simulate(idx, act=0.15, trails=(0.12, 0.09, 0.07), wiggle=False):
    entry = SIM_PATH[0]
    stage = 0
    hwm = entry
    sold = []
    for k in range(idx + 1):
        p = SIM_PATH[k]
        if stage == 0:
            if p >= entry * (1.0 + act):
                stage = 1
                hwm = p
            continue
        if stage > 3:
            continue
        hwm = max(hwm, p)
        addon = min(sim_vol(k) * 1.0, 0.10) if wiggle else 0.0
        eff_trail = trails[stage - 1] + addon
        if p <= hwm * (1.0 - eff_trail):
            sold.append({"k": k, "p": p, "stage": stage, "frac": PORTIONS[stage - 1]})
            stage += 1
            hwm = p
    live = 1 <= stage <= 3
    addon_now = min(sim_vol(idx) * 1.0, 0.10) if wiggle else 0.0
    stop = hwm * (1.0 - (trails[stage - 1] + addon_now)) if live else None
    return {
        "stage": stage,
        "hwm": hwm,
        "sold": sold,
        "price": SIM_PATH[idx],
        "entry": entry,
        "done": stage > 3,
        "stop": stop,
    }

def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))

def ease_out_cubic(t):
    t = clamp(t)
    return 1.0 - (1.0 - t) ** 3

def ease_in_out_cubic(t):
    t = clamp(t)
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2

def interp(frame, f0, f1, v0, v1, ease=ease_in_out_cubic):
    if frame <= f0:
        return v0
    if frame >= f1:
        return v1
    t = (frame - f0) / float(f1 - f0)
    return v0 + (v1 - v0) * ease(t)

# ==============================================================================
# MASTER 2:36 (156.0s / 4,680 FRAMES / 78 BARS) SCENE SCHEDULE
# ==============================================================================
SCENES = [
    {
        "id": "cover",
        "step": 0,
        "start": 0,
        "end": 239,  # 00:00 - 00:08 (8s)
        "route": "home",
        "url": "pulsetrail.app",
        "num": "00",
        "label": "AUTONOMOUS STOP-LOSS",
        "headline": "Ride. Ratchet. Sleep.",
        "sub": "Non-custodial trailing protection across Base (8453) & Reactive (1597).",
        "subtitle": "PulseTrail: autonomous smart stop-losses on Base that ratchet up as your tokens climb, and cash out into USDC in three steps.",
        "vo_tempo": 1.06,
        "vo_dur": 7.69,
    },
    {
        "id": "hero_intro",
        "step": 1,
        "start": 240,
        "end": 599,  # 00:08 - 00:20 (12s)
        "route": "home",
        "url": "pulsetrail.app/#home",
        "num": "01",
        "label": "NON-CUSTODIAL PROTECTION",
        "headline": "Ride the pump. Lock the gains.",
        "sub": "Zero protocol fees, zero Telegram bot risk, and your keys never leave your wallet.",
        "subtitle": "Traditional stop-losses get wicked out early or require handing your private keys to a Telegram bot. PulseTrail runs entirely on-chain.",
        "vo_tempo": 0.94,
        "vo_dur": 8.93,
    },
    {
        "id": "simulate",
        "step": 1,
        "start": 600,
        "end": 1139,  # 00:20 - 00:38 (18s)
        "route": "home",
        "url": "pulsetrail.app/#home",
        "num": "01",
        "label": "PROFIT-ACTIVATED RATCHET",
        "headline": "Play a simulated pump",
        "sub": "Waits for +15% profit, trails every peak, and scales out 40% / 30% / 30% into USDC.",
        "subtitle": "Click Play a simulated pump: protection stays dormant until plus fifteen percent, ratchets up with every new peak, and scales out forty, thirty, and thirty percent into USDC.",
        "vo_tempo": 0.92,
        "vo_dur": 12.62,
    },
    {
        "id": "why_compare",
        "step": 1,
        "start": 1140,
        "end": 1559,  # 00:38 - 00:52 (14s)
        "route": "home_why",
        "url": "pulsetrail.app/#why",
        "num": "01",
        "label": "WHY PULSETRAIL WINS",
        "headline": "Three steps. No jargon.",
        "sub": "Beats custodial Telegram bots and manual panic-selling on 3 AM pumps and wicks.",
        "subtitle": "Scroll down to compare: Three steps, no jargon. When a three AM pump or sudden wick hits, PulseTrail widens its cushion and banks gains while you sleep.",
        "vo_tempo": 0.93,
        "vo_dur": 9.84,
    },
    {
        "id": "configure_token",
        "step": 2,
        "start": 1560,
        "end": 2039,  # 00:52 - 01:08 (16s)
        "route": "app",
        "url": "pulsetrail.app/#app",
        "num": "02",
        "label": "TOKEN & POOL DISCOVERY",
        "headline": "Pick token & deposit size",
        "sub": "Choose PTRAIL, WETH, BRETT, DEGEN, or paste any Base Uniswap V2 / Aerodrome pair.",
        "subtitle": "Open Protect to pick your token and deposit size: select PTRAIL, WETH, BRETT, or DEGEN on Base, auto-detect its liquidity pool, and enter ten thousand tokens.",
        "vo_tempo": 0.93,
        "vo_dur": 11.65,
    },
    {
        "id": "configure_preset",
        "step": 2,
        "start": 2040,
        "end": 2459,  # 01:08 - 01:22 (14s)
        "route": "app",
        "url": "pulsetrail.app/#app",
        "num": "02",
        "label": "STRATEGY PRESETS & ESTIMATOR",
        "headline": "Meme coin rocket preset",
        "sub": "Starts at +15% with 12% / 9% / 7% buffers — estimator projects ~$1,621 (+62%).",
        "subtitle": "Compare Conservative lock and Meme coin rocket: the live estimator calculates your exact three-step USDC payout after the pool swap fee, projecting sixteen hundred twenty-one dollars.",
        "vo_tempo": 0.95,
        "vo_dur": 12.22,
    },
    {
        "id": "shield_checks",
        "step": 3,
        "start": 2460,
        "end": 2879,  # 01:22 - 01:36 (14s)
        "route": "app",
        "url": "pulsetrail.app/#app",
        "num": "03",
        "label": "PRE-FLIGHT RISK SHIELD",
        "headline": "On-chain safety verification",
        "sub": "Checks honeypot sellability, pool share (0.42% < 5%), and reserve depth ($2.4M).",
        "subtitle": "Before a single token is deposited, the on-chain Safety Check verifies honeypot sellability, pool share impact under five percent, and healthy reserve depth.",
        "vo_tempo": 0.94,
        "vo_dur": 10.44,
    },
    {
        "id": "shield_wiggle",
        "step": 3,
        "start": 2880,
        "end": 3239,  # 01:36 - 01:48 (12s)
        "route": "app",
        "url": "pulsetrail.app/#app",
        "num": "03",
        "label": "VOLATILITY-ADAPTIVE BUFFER",
        "headline": "Smart wiggle room (+10%)",
        "sub": "8-tick rolling volatility engine widens trail (12% -> 22%) during violent wicks.",
        "subtitle": "Switch to Pro mode and enable Smart wiggle room: an eight-tick rolling volatility buffer automatically widens your stop during wild market swings.",
        "vo_tempo": 0.95,
        "vo_dur": 8.38,
    },
    {
        "id": "vault",
        "step": 4,
        "start": 3240,
        "end": 3659,  # 01:48 - 02:02 (14s)
        "route": "app",
        "url": "pulsetrail.app/#app",
        "num": "04",
        "label": "ONE-CLICK VAULT ESCROW",
        "headline": "Activate auto-protection",
        "sub": "Deposits into Base Mainnet vault (0xCacF...fAde) with ~$0.008 gas in ~200ms.",
        "subtitle": "Click Activate auto-protection: approve and register Position Number One in the Base Mainnet vault in a two-hundred-millisecond Flashblock for under a cent.",
        "vo_tempo": 0.94,
        "vo_dur": 9.50,
    },
    {
        "id": "inspect",
        "step": 5,
        "start": 3660,
        "end": 4139,  # 02:02 - 02:18 (16s)
        "route": "positions",
        "url": "pulsetrail.app/#positions",
        "num": "05",
        "label": "LIVE POSITION INSPECTOR",
        "headline": "Real-time peak & viral proof",
        "sub": "Monitors PTRAIL #1 on-chain, banks +552 USDC on Step 1, and shares 1-click proof.",
        "subtitle": "Under My positions, watch the Reactive Brain ratchet your live peak to one dollar eighty-four, bank five hundred fifty-two USDC on Step One, and copy your shareable proof.",
        "vo_tempo": 0.93,
        "vo_dur": 11.27,
    },
    {
        "id": "proof",
        "step": 6,
        "start": 4140,
        "end": 4679,  # 02:18 - 02:36 (18s)
        "route": "proof",
        "url": "pulsetrail.app/#proof",
        "num": "06",
        "label": "VERIFIED ON-CHAIN LOOP",
        "headline": "2.0s cross-chain execution",
        "sub": "Base Sync (T0) -> Reactive Brain (T1, 1.0s) -> Base Callback Swap (T2, 1.0s).",
        "subtitle": "Every contract and two-second cross-chain callback is verified on BaseScan and ReactScan. Test it yourself with zero risk at pulsetrail.app — Ride. Ratchet. Sleep.",
        "vo_tempo": 0.92,
        "vo_dur": 11.00,
    },
]

def get_scene(frame):
    for s in SCENES:
        if s["start"] <= frame <= s["end"]:
            return s
    return SCENES[-1]

# ==============================================================================
# 1. AUDIO SYNTHESIZER (120 BPM Original Soundtrack + Frame-Locked UI SFX, 156s)
# ==============================================================================
def generate_soundtrack(wav_path):
    sr = 48000
    n_samples = int(DURATION_SEC * sr)

    left = np.zeros(n_samples, dtype=np.float32)
    right = np.zeros(n_samples, dtype=np.float32)

    chords = [
        [174.61, 220.00, 261.63, 329.63, 392.00],  # Fmaj9
        [164.81, 196.00, 246.94, 293.66, 392.00],  # Em7
        [146.83, 174.61, 220.00, 261.63, 329.63],  # Dm9
        [130.81, 164.81, 196.00, 246.94, 293.66],  # Cmaj9
    ]

    bar_len = int(2.0 * sr)
    total_bars = int(DURATION_SEC // 2)  # 78 bars
    for bar in range(total_bars):
        s0 = bar * bar_len
        s1 = min(n_samples, s0 + bar_len)
        bt = np.arange(s1 - s0, dtype=np.float32) / sr
        freqs = chords[bar % 4]

        duck = 1.0 - 0.35 * np.exp(-((bt % 0.5) * 14.0))
        env = np.minimum(bt / 0.04, 1.0) * np.exp(-bt * 0.65) * duck
        pad_l = np.zeros_like(bt)
        pad_r = np.zeros_like(bt)
        for i, f in enumerate(freqs):
            detune = 1.0015 if i % 2 == 0 else 0.9985
            sig_l = np.sin(2 * np.pi * f * bt) + 0.25 * np.sin(2 * np.pi * f * 2 * bt) * np.exp(-bt * 2.5)
            sig_r = np.sin(2 * np.pi * f * detune * bt + 0.3) + 0.25 * np.sin(2 * np.pi * f * 2 * bt) * np.exp(-bt * 2.5)
            pan = 0.3 + 0.4 * (i / 4.0)
            pad_l += sig_l * (1.0 - pan)
            pad_r += sig_r * pan

        root_f = freqs[0] * 0.5
        bass_env = np.minimum((bt % 0.5) / 0.015, 1.0) * np.exp(-(bt % 0.5) * 4.5)
        bass = np.sin(2 * np.pi * root_f * bt) * bass_env * 0.14

        left[s0:s1] += (pad_l * env * 0.045) + bass
        right[s0:s1] += (pad_r * env * 0.045) + bass

        if 4 <= bar < 74:
            for beat in range(4):
                b_start = s0 + int(beat * 0.5 * sr)
                if b_start >= n_samples:
                    break
                if beat in (0, 2):
                    k_len = min(int(0.18 * sr), n_samples - b_start)
                    kt = np.arange(k_len, dtype=np.float32) / sr
                    k_freq = 52.0 + 95.0 * np.exp(-kt * 38.0)
                    k_phase = 2 * np.pi * np.cumsum(k_freq) / sr
                    kick = np.sin(k_phase) * np.exp(-kt * 16.0) * 0.15
                    left[b_start:b_start + k_len] += kick
                    right[b_start:b_start + k_len] += kick
                if beat in (1, 3):
                    r_len = min(int(0.06 * sr), n_samples - b_start)
                    rt = np.arange(r_len, dtype=np.float32) / sr
                    rim = (np.sin(2 * np.pi * 820 * rt) + 0.6 * np.sin(2 * np.pi * 1450 * rt)) * np.exp(-rt * 75.0) * 0.045
                    left[b_start:b_start + r_len] += rim * 0.9
                    right[b_start:b_start + r_len] += rim * 1.1
                h_start = b_start + int(0.25 * sr)
                if h_start < n_samples:
                    h_len = min(int(0.05 * sr), n_samples - h_start)
                    ht = np.arange(h_len, dtype=np.float32) / sr
                    rng = np.random.default_rng(bar * 10 + beat)
                    hat = rng.standard_normal(h_len).astype(np.float32) * np.exp(-ht * 95.0) * 0.02
                    left[h_start:h_start + h_len] += hat * 1.1
                    right[h_start:h_start + h_len] += hat * 0.85

    def add_sfx(frame_idx, sfx_l, sfx_r=None):
        if sfx_r is None:
            sfx_r = sfx_l
        idx0 = int((frame_idx / float(FPS)) * sr)
        if idx0 >= n_samples:
            return
        L = min(len(sfx_l), n_samples - idx0)
        left[idx0:idx0 + L] += sfx_l[:L]
        right[idx0:idx0 + L] += sfx_r[:L]

    def make_click(heavy=False):
        dur = int(0.045 * sr)
        ct = np.arange(dur, dtype=np.float32) / sr
        f1 = 1100.0 if not heavy else 750.0
        f2 = 2400.0 if not heavy else 1600.0
        amp = 0.26 if not heavy else 0.34
        return (np.sin(2 * np.pi * f1 * ct) * np.exp(-ct * 140.0) +
                0.6 * np.sin(2 * np.pi * f2 * ct) * np.exp(-ct * 260.0)) * amp

    def make_key(seed=1):
        dur = int(0.035 * sr)
        kt = np.arange(dur, dtype=np.float32) / sr
        f = 1500.0 + (seed % 5) * 140.0
        return np.sin(2 * np.pi * f * kt) * np.exp(-kt * 180.0) * 0.20

    def make_snap():
        dur = int(0.12 * sr)
        st = np.arange(dur, dtype=np.float32) / sr
        s1 = np.sin(2 * np.pi * 523.25 * st) * np.exp(-st * 45.0)
        s2 = np.sin(2 * np.pi * 783.99 * np.maximum(0, st - 0.035)) * np.exp(-np.maximum(0, st - 0.035) * 35.0) * (st >= 0.035)
        return (s1 + s2) * 0.24

    def make_ping(mult=1.0):
        dur = int(0.28 * sr)
        pt = np.arange(dur, dtype=np.float32) / sr
        f = 880.0 * mult
        return (np.sin(2 * np.pi * f * pt) + 0.35 * np.sin(2 * np.pi * f * 2.0 * pt)) * np.exp(-pt * 16.0) * 0.24

    def make_cash_out(stage=1):
        dur = int(0.45 * sr)
        ct = np.arange(dur, dtype=np.float32) / sr
        base = 523.25 * (1.0 + 0.12 * (stage - 1))
        notes = [base, base * 1.25, base * 1.5, base * 2.0]
        sig_l = np.zeros_like(ct)
        sig_r = np.zeros_like(ct)
        for i, nf in enumerate(notes):
            delay = i * 0.045
            dt = np.maximum(0.0, ct - delay)
            mask = (ct >= delay).astype(np.float32)
            tone = (np.sin(2 * np.pi * nf * dt) + 0.4 * np.sin(2 * np.pi * nf * 2 * dt)) * np.exp(-dt * 12.0) * mask
            sig_l += tone * (0.8 if i % 2 == 0 else 0.5)
            sig_r += tone * (0.5 if i % 2 == 0 else 0.8)
        return sig_l * 0.22, sig_r * 0.22

    def make_whoosh():
        dur = int(0.26 * sr)
        wt = np.arange(dur, dtype=np.float32) / sr
        env = np.sin(np.pi * wt / 0.26) ** 2
        f_sweep = 180.0 + 420.0 * (wt / 0.26)
        phase = 2 * np.pi * np.cumsum(f_sweep) / sr
        sig = np.sin(phase) * env * 0.11
        return sig * 0.9, sig * 1.1

    def make_tx_confirm():
        dur = int(0.65 * sr)
        tt = np.arange(dur, dtype=np.float32) / sr
        notes = [523.25, 659.25, 783.99, 1046.50]
        sig = np.zeros_like(tt)
        for i, nf in enumerate(notes):
            d = i * 0.055
            dt = np.maximum(0.0, tt - d)
            mask = (tt >= d).astype(np.float32)
            sig += (np.sin(2 * np.pi * nf * dt) + 0.3 * np.sin(2 * np.pi * nf * 2 * dt)) * np.exp(-dt * 7.5) * mask
        return sig * 0.20

    # Synced SFX across the 2m36s (4,680-frame) timeline
    add_sfx(0, make_tx_confirm())
    add_sfx(240, *make_whoosh())
    add_sfx(560, make_click(heavy=True))  # Click Play a simulated pump
    add_sfx(690, make_ping(1.0))          # +15% activation crossed
    add_sfx(780, make_ping(1.15))         # HWM $1.65
    add_sfx(840, make_ping(1.3))          # Peak $2.00
    add_sfx(895, *make_cash_out(1))       # Batch 1 sold
    add_sfx(965, *make_cash_out(2))       # Batch 2 sold
    add_sfx(1040, *make_cash_out(3))      # Batch 3 sold

    add_sfx(1140, *make_whoosh())         # Scroll to Why PulseTrail
    add_sfx(1320, make_ping(1.2))         # Highlight comparison table

    add_sfx(1560, *make_whoosh())         # Navigate to Protect (#app)
    add_sfx(1600, make_click())           # Click Protect nav
    add_sfx(1680, make_click())           # Click WETH
    add_sfx(1740, make_click())           # Click BRETT
    add_sfx(1800, make_click())           # Click PTRAIL
    add_sfx(1860, make_click())           # Focus Amount input
    for idx, kf in enumerate([1880, 1892, 1904, 1916, 1928]):
        add_sfx(kf, make_key(idx))

    add_sfx(2040, *make_whoosh())
    add_sfx(2130, make_click())           # Click Conservative lock
    add_sfx(2220, make_snap())            # Select Meme coin rocket
    add_sfx(2320, make_ping(1.25))        # Estimator total highlight

    add_sfx(2460, *make_whoosh())         # Pan to Safety Check
    add_sfx(2550, make_ping(1.0))         # Check 1: Honeypot shield
    add_sfx(2640, make_ping(1.2))         # Check 2: Pool depth 0.42%
    add_sfx(2730, make_ping(1.5))         # Check 3: Pool health $2.4M

    add_sfx(2880, *make_whoosh())         # Pan to Pro & Wiggle room
    add_sfx(2920, make_click())           # Switch to Pro tab
    add_sfx(3010, make_snap())            # Enable Smart wiggle room

    add_sfx(3240, *make_whoosh())
    add_sfx(3310, make_click(heavy=True)) # Click Activate auto-protection
    add_sfx(3400, make_ping(1.1))         # Wallet approve
    add_sfx(3490, make_tx_confirm())      # Position #1 Registered toast

    add_sfx(3660, *make_whoosh())         # Transition to My positions
    add_sfx(3780, make_ping(1.25))        # HWM ratchet $1.84
    add_sfx(3880, *make_cash_out(1))      # Banked 552.00 USDC
    add_sfx(3990, make_click())           # Click Copy Proof

    add_sfx(4140, *make_whoosh())         # Transition to Proof (#proof)
    add_sfx(4230, make_ping(1.35))        # 2.0s latency benchmark
    add_sfx(4440, make_tx_confirm())      # TEST IT YOURSELF modal card

    fade_len = int(1.5 * sr)
    fade_curve = np.linspace(1.0, 0.0, fade_len, dtype=np.float32)
    left[-fade_len:] *= fade_curve
    right[-fade_len:] *= fade_curve

    stereo = np.stack([np.tanh(left * 1.15), np.tanh(right * 1.15)], axis=-1)
    pcm16 = (stereo * 30000.0).astype(np.int16)

    with wave.open(wav_path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm16.tobytes())

# ==============================================================================
# 2. UI PRIMITIVES (Exact Neo-Brutalist PulseTrail Styling)
# ==============================================================================
def draw_neo_card(draw, box, fill=CARD_BG, outline=INK, width=3, radius=20, shadow_offset=(5, 6), shadow_col=(17, 17, 17)):
    x0, y0, x1, y1 = box
    if shadow_offset:
        sx, sy = shadow_offset
        draw.rounded_rectangle((x0 + sx, y0 + sy, x1 + sx, y1 + sy), radius=radius, fill=shadow_col)
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)

def draw_pill(draw, x, y, text, bg=CARD_BG, fg=INK, border=INK, dot_col=None, check_col=None, font_size=13, pad_x=12, pad_y=5):
    f = get_font("mono_bold", font_size)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    icon_space = 18 if (dot_col or check_col) else 0
    w = tw + pad_x * 2 + icon_space
    h = max(th + pad_y * 2, 26)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=bg, outline=border, width=2)
    cx = x + pad_x
    if dot_col:
        draw.ellipse((cx, y + h // 2 - 4, cx + 8, y + h // 2 + 4), fill=dot_col)
        cx += 15
    elif check_col:
        draw_check_icon(draw, cx + 5, y + h // 2, size=10, color=check_col, width=2)
        cx += 16
    draw.text((cx, y + (h - th) // 2 - 1), text, font=f, fill=fg)
    return w, h

def draw_button(draw, box, text, bg=INK, fg=PAPER_BG, font_size=16, pressed=False, radius=12, has_check=False):
    x0, y0, x1, y1 = box
    off = 2 if pressed else 5
    if pressed:
        x0 += 2
        y0 += 2
        x1 += 2
        y1 += 2
    draw.rounded_rectangle((x0 + off, y0 + off, x1 + off, y1 + off), radius=radius, fill=INK)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=bg, outline=INK, width=3)
    f = get_font("bold", font_size)
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    extra = 22 if has_check else 0
    tx = (x0 + x1 - (tw + extra)) // 2
    ty = (y0 + y1 - th) // 2 - 2
    if has_check:
        draw_check_icon(draw, tx + 7, (y0 + y1) // 2, size=12, color=fg, width=3)
        tx += 22
    draw.text((tx, ty), text, font=f, fill=fg)

def draw_pointer_cursor(img, x, y, click_age=None):
    draw = ImageDraw.Draw(img, "RGBA")
    if click_age is not None and 0 <= click_age <= 18:
        prog = click_age / 18.0
        r = int(8 + 38 * ease_out_cubic(prog))
        alpha = int(230 * (1.0 - prog))
        draw.ellipse((x - r, y - r, x + r, y + r), outline=(224, 36, 36, alpha), width=4)
        r2 = int(4 + 22 * ease_out_cubic(prog))
        draw.ellipse((x - r2, y - r2, x + r2, y + r2), outline=(0, 245, 155, alpha), width=3)

    pts = [
        (x, y),
        (x, y + 26),
        (x + 7, y + 20),
        (x + 12, y + 31),
        (x + 17, y + 29),
        (x + 12, y + 18),
        (x + 20, y + 18),
    ]
    shadow_pts = [(px + 2, py + 3) for (px, py) in pts]
    draw.polygon(shadow_pts, fill=(0, 0, 0, 140))
    draw.polygon(pts, fill=(255, 255, 255, 255), outline=(17, 17, 17, 255))
    draw.line(pts + [pts[0]], fill=(17, 17, 17, 255), width=2)

# ==============================================================================
# 3. VIRTUAL BROWSER PAGE RENDERER WITH STATE CACHING (1600 x 920)
# ==============================================================================
_BG_DOT_CANVAS = None
def get_dotted_page_canvas(w=1600, h=920):
    global _BG_DOT_CANVAS
    if _BG_DOT_CANVAS is not None and _BG_DOT_CANVAS.size == (w, h):
        return _BG_DOT_CANVAS.copy()
    img = Image.new("RGB", (w, h), PAPER_BG)
    draw = ImageDraw.Draw(img)
    for y in range(10, h, 18):
        for x in range(10, w, 18):
            draw.rectangle((x, y, x + 1, y + 1), fill=DOT_COL)
    _BG_DOT_CANVAS = img
    return img.copy()

def draw_app_header(img, draw, active_route="home"):
    w = img.width
    draw.rectangle((0, 0, w, 68), fill=PAPER_BG)
    draw.line((0, 68, w, 68), fill=INK, width=3)

    logo = get_logo(34)
    img.paste(logo, (48, 17), logo)
    f_logo = get_font("display", 23)
    draw.text((92, 18), "PulseTrail", font=f_logo, fill=INK)
    draw.rounded_rectangle((228, 22, 278, 46), radius=6, fill=GREEN, outline=INK, width=2)
    draw.text((236, 25), "BASE", font=get_font("mono_bold", 13), fill=INK)

    nav_route = "home" if active_route == "home_why" else active_route
    navs = [("app", "Protect"), ("positions", "My positions"), ("proof", "Proof"), ("docs", "Docs")]
    nx = 540
    for k, label in navs:
        f_nav = get_font("bold", 16)
        draw.text((nx, 23), label, font=f_nav, fill=INK)
        bbox = draw.textbbox((nx, 23), label, font=f_nav)
        if k == nav_route:
            draw.line((nx, bbox[3] + 4, bbox[2], bbox[3] + 4), fill=INK, width=3)
        nx = bbox[2] + 34

    draw_pill(draw, 1075, 19, "Base · fast (<2s)", bg=CARD_BG, fg=INK, dot_col=(31, 191, 75), font_size=12)
    draw_pill(draw, 1265, 19, "White", bg=CARD_BG, fg=INK, dot_col=AMBER, font_size=12)
    draw_pill(draw, 1365, 19, "0x71C...89A (Base)", bg=INK, fg=PAPER_BG, font_size=12)

def draw_ratchet_chart_widget(draw, x0, y0, w, h, sim_idx, wiggle=False):
    sim = run_simulate(sim_idx, act=0.15, trails=(0.12, 0.09, 0.07), wiggle=wiggle)
    draw.text((x0, y0), "Price vs. your protection", font=get_font("bold", 18), fill=INK)
    draw_pill(draw, x0 + w - 185, y0 - 2, "Pulse brain online", bg=CARD_BG, fg=INK, dot_col=(31, 191, 75), font_size=12)

    cx0, cy0 = x0, y0 + 36
    cw, ch = w, h - 165
    draw.rounded_rectangle((cx0, cy0, cx0 + cw, cy0 + ch), radius=14, fill=PAPER_BG, outline=INK, width=2)

    lo, hi = 0.80, 2.20
    def px(k):
        return int(cx0 + 18 + (k / 79.0) * (cw - 36))
    def py(v):
        return int(cy0 + ch - 18 - ((v - lo) / (hi - lo)) * (ch - 38))

    y_ent = py(1.0)
    for dx in range(cx0 + 14, cx0 + cw - 14, 14):
        draw.line((dx, y_ent, min(dx + 8, cx0 + cw - 14), y_ent), fill=(31, 191, 75), width=2)
    draw.text((cx0 + 20, y_ent - 18), "Entry $1.00", font=get_font("mono_bold", 12), fill=(31, 191, 75))

    y_act = py(1.15)
    for dx in range(cx0 + 14, cx0 + cw - 14, 14):
        draw.line((dx, y_act, min(dx + 8, cx0 + cw - 14), y_act), fill=PURPLE, width=2)
    draw.text((cx0 + 20, y_act - 18), "Starts at +15% ($1.15)", font=get_font("mono_bold", 12), fill=PURPLE)

    if sim["stage"] >= 1:
        y_hwm = py(sim["hwm"])
        draw.line((cx0 + 14, y_hwm, cx0 + cw - 14, y_hwm), fill=AMBER, width=3)
        draw.text((cx0 + cw - 115, y_hwm - 19), f"Peak ${sim['hwm']:.2f}", font=get_font("mono_bold", 12), fill=(195, 115, 0))

    if sim["stop"] is not None:
        y_stp = py(sim["stop"])
        draw.line((cx0 + 14, y_stp, cx0 + cw - 14, y_stp), fill=RED, width=3)
        draw.text((cx0 + cw - 115, y_stp + 5), f"Stop ${sim['stop']:.2f}", font=get_font("mono_bold", 12), fill=RED)

    pts = [(px(k), py(SIM_PATH[k])) for k in range(sim_idx + 1)]
    if len(pts) >= 2:
        draw.line(pts, fill=INK, width=4, joint="curve")

    for s in sim["sold"]:
        sx, sy = px(s["k"]), py(s["p"])
        draw.ellipse((sx - 13, sy - 13, sx + 13, sy + 13), fill=RED, outline=INK, width=3)
        draw.text((sx - 4, sy - 8), str(s["stage"]), font=get_font("mono_bold", 13), fill=(255, 255, 255))

    hx, hy = px(sim_idx), py(sim["price"])
    draw.ellipse((hx - 8, hy - 8, hx + 8, hy + 8), fill=NEON_GREEN, outline=INK, width=3)

    cy_ctrl = cy0 + ch + 10
    draw.rounded_rectangle((cx0, cy_ctrl, cx0 + 68, cy_ctrl + 32), radius=8, fill=INK, outline=INK, width=2)
    draw.text((cx0 + 14, cy_ctrl + 6), "Pause" if 0 < sim_idx < 79 else "Play", font=get_font("bold", 13), fill=PAPER_BG)
    sl_x0, sl_x1 = cx0 + 82, cx0 + cw - 82
    sl_y = cy_ctrl + 16
    draw.line((sl_x0, sl_y, sl_x1, sl_y), fill=DOT_COL, width=6)
    knob_x = int(sl_x0 + (sim_idx / 79.0) * (sl_x1 - sl_x0))
    draw.line((sl_x0, sl_y, knob_x, sl_y), fill=RED, width=6)
    draw.ellipse((knob_x - 8, sl_y - 8, knob_x + 8, sl_y + 8), fill=RED, outline=INK, width=2)
    draw.text((cx0 + cw - 68, cy_ctrl + 6), f"${sim['price']:.2f}", font=get_font("mono_bold", 16), fill=INK)

    cy_step = cy_ctrl + 44
    if sim["sold"]:
        last = sim["sold"][-1]
        usdc_amt = int(round(last["frac"] * DEMO_USD * last["p"]))
        draw.rounded_rectangle((cx0, cy_step - 2, cx0 + cw, cy_step + 24), radius=6, fill=(220, 252, 231), outline=GREEN, width=2)
        draw_check_icon(draw, cx0 + 16, cy_step + 11, size=10, color=(6, 95, 70), width=2)
        draw.text((cx0 + 28, cy_step + 2), f"Batch {last['stage']} sold! +${usdc_amt} USDC secured to wallet", font=get_font("mono_bold", 13), fill=(6, 95, 70))
        cy_step += 32

    steps_meta = [
        ("Monitoring", "Waiting for +15%"),
        ("Step 1: 40%", "Sells 40% on dip"),
        ("Step 2: 30%", "Sells 30% next"),
        ("Step 3: 30%", "Sells last 30%"),
    ]
    active_idx = min(sim["stage"], 3)
    gap = 8
    sw = (cw - gap * 3) // 4
    for n, (st_title, st_sub) in enumerate(steps_meta):
        sx0 = cx0 + n * (sw + gap)
        is_on = sim["done"] or (n == active_idx)
        bg_c = NEON_GREEN if is_on else PAPER_BG
        if is_on:
            draw.rounded_rectangle((sx0 + 2, cy_step + 3, sx0 + sw + 2, cy_step + 55), radius=10, fill=INK)
        draw.rounded_rectangle((sx0, cy_step, sx0 + sw, cy_step + 52), radius=10, fill=bg_c, outline=INK, width=2)
        draw.text((sx0 + 8, cy_step + 6), st_title, font=get_font("bold", 12), fill=INK)
        sub_txt = f"Peak ${sim['hwm']:.2f}" if (n == active_idx and sim["stage"] >= 1 and not sim["done"]) else st_sub
        draw.text((sx0 + 8, cy_step + 26), sub_txt, font=get_font("mono", 11), fill=INK if is_on else MUTED)

_PAGE_CACHE = {"key": None, "img": None}

def get_page_state_key(frame, scene):
    r = scene["route"]
    if r == "home":
        btn_pressed = 556 <= frame <= 566
        sim_idx = 0 if frame < 600 else int(clamp((frame - 600) / 460.0) * 79)
        return ("home", btn_pressed, sim_idx)
    elif r == "home_why":
        hi_row = 0
        if frame >= 1420:
            hi_row = 4
        elif frame >= 1360:
            hi_row = 3
        elif frame >= 1300:
            hi_row = 2
        elif frame >= 1240:
            hi_row = 1
        return ("home_why", hi_row)
    elif r == "app":
        is_pro = frame >= 2920
        if 1680 <= frame < 1740:
            sel_tok = "WETH"
        elif 1740 <= frame < 1800:
            sel_tok = "BRETT"
        else:
            sel_tok = "PTRAIL"
        amt_focus = 1860 <= frame <= 1980
        if frame >= 1928:
            typed_amt = "10,000"
        elif frame >= 1916:
            typed_amt = "1000|"
        elif frame >= 1904:
            typed_amt = "100|"
        elif frame >= 1892:
            typed_amt = "10|"
        elif frame >= 1880:
            typed_amt = "1|"
        elif frame >= 1860:
            typed_amt = "|"
        else:
            typed_amt = "0.0"

        if frame < 2220:
            sel_preset = "safe"
        else:
            sel_preset = "rocket"

        wiggle_on = frame >= 3010
        if 3310 <= frame < 3400:
            btn_state = "approving"
        elif 3400 <= frame < 3490:
            btn_state = "creating"
        elif frame >= 3490:
            btn_state = "active"
        else:
            btn_state = "idle"
        btn_pressed = 3308 <= frame <= 3318

        c1_ok = frame >= 1940
        c2_ok = frame >= 1950
        c3_ok = frame >= 1960
        c_hi = 1 if (2550 <= frame <= 2620) else (2 if (2640 <= frame <= 2710) else (3 if (2730 <= frame <= 2810) else 0))
        return ("app", is_pro, sel_tok, amt_focus, typed_amt, sel_preset, wiggle_on, btn_state, btn_pressed, c1_ok, c2_ok, c3_ok, c_hi)
    elif r == "positions":
        step1_done = frame >= 3880
        cur_hwm = 1.84 if frame >= 3780 else 1.48
        copied = frame >= 3990
        copy_pressed = 3988 <= frame <= 3996
        return ("positions", step1_done, cur_hwm, copied, copy_pressed)
    elif r == "proof":
        return ("proof",)
    return (r, frame)

def render_browser_page(frame, scene):
    key = get_page_state_key(frame, scene)
    if _PAGE_CACHE["key"] == key and _PAGE_CACHE["img"] is not None:
        return _PAGE_CACHE["img"].copy()

    page = get_dotted_page_canvas(1600, 920)
    draw = ImageDraw.Draw(page)
    draw_app_header(page, draw, active_route=scene["route"])

    if scene["route"] == "home":
        _, btn_pressed, sim_idx = key
        draw.text((64, 155), "Ride the pump.", font=get_font("display", 58), fill=INK)
        draw.text((64, 222), "Lock the gains.", font=get_font("display", 58), fill=INK)
        draw.text((64, 289), "Sleep.", font=get_font("display", 58), fill=GREEN)

        lead_lines = [
            "Autonomous smart stop-losses that ratchet up as your",
            "tokens climb, then cash you out into USDC in three steps",
            "if they dip. Your keys never leave your wallet.",
        ]
        for idx, ln in enumerate(lead_lines):
            draw.text((64, 382 + idx * 30), ln, font=get_font("sans", 21), fill=MUTED)

        draw_button(draw, (64, 500, 318, 556), "Play a simulated pump", bg=RED, fg=(255, 255, 255), font_size=18, pressed=btn_pressed)
        draw.text((346, 515), "Protect a position ->", font=get_font("bold", 19), fill=INK)
        draw.line((346, 542, 540, 542), fill=INK, width=3)

        draw.text((64, 584), "Non-custodial. Runs on Base smart contracts. No Telegram bot holds your key.", font=get_font("mono", 13), fill=MUTED)

        draw_pill(draw, 64, 632, "0% Protocol Fee", bg=CARD_BG, fg=INK, check_col=GREEN, font_size=13)
        draw_pill(draw, 252, 632, "Non-Custodial Vault", bg=CARD_BG, fg=INK, check_col=GREEN, font_size=13)
        draw_pill(draw, 476, 632, "Sub-2s Reactive Loop", bg=CARD_BG, fg=INK, check_col=GREEN, font_size=13)

        draw_neo_card(draw, (760, 118, 1536, 825), fill=CARD_BG, outline=INK, width=4, radius=24, shadow_offset=(8, 10))
        draw_ratchet_chart_widget(draw, 792, 146, 712, 650, sim_idx=sim_idx, wiggle=False)

    elif scene["route"] == "home_why":
        _, hi_row = key
        # Real lower section of #home from frontend/src/content/home.html!
        draw.text((64, 92), "Three steps. No jargon.", font=get_font("display", 38), fill=INK)
        draw.text((64, 140), "Pick what to protect, let it ride, and get paid on the dip.", font=get_font("sans", 17), fill=MUTED)

        how_cards = [
            ("1", "Pick your token", "Choose how much to protect and how much cushion you want. No pool addresses to paste."),
            ("2", "Let it ride", "As the price climbs, your stop price moves up on its own. It never moves down."),
            ("3", "Cash out on dips", "If price pulls back, 40%, then 30%, then 30% is sold into USDC. You keep skin in the game."),
        ]
        cw = 468
        for idx, (num_s, h_title, h_desc) in enumerate(how_cards):
            cx0 = 64 + idx * (cw + 34)
            draw_neo_card(draw, (cx0, 180, cx0 + cw, 352), fill=CARD_BG, outline=INK, width=3, radius=20, shadow_offset=(5, 6))
            draw.rounded_rectangle((cx0 + 24, 200, cx0 + 62, 238), radius=10, fill=NEON_GREEN, outline=INK, width=3)
            draw.text((cx0 + 37, 205), num_s, font=get_font("mono_bold", 20), fill=INK)
            draw.text((cx0 + 24, 250), h_title, font=get_font("bold", 22), fill=INK)
            # Wrap description into 2 lines
            words = h_desc.split(" ")
            mid = len(words) // 2 + 1
            draw.text((cx0 + 24, 286), " ".join(words[:mid]), font=get_font("sans", 15), fill=MUTED)
            draw.text((cx0 + 24, 310), " ".join(words[mid:]), font=get_font("sans", 15), fill=MUTED)

        # Why PulseTrail? Comparison Table from home.html
        draw.text((64, 388), "Why PulseTrail?", font=get_font("display", 34), fill=INK)
        draw.text((360, 398), "Compared with the usual options.", font=get_font("sans", 17), fill=MUTED)

        draw_neo_card(draw, (64, 444, 1536, 756), fill=CARD_BG, outline=INK, width=3, radius=18, shadow_offset=(6, 7))
        # Table Header
        draw.rounded_rectangle((64, 444, 1536, 500), radius=15, fill=INK)
        draw.rectangle((1120, 444, 1536, 500), fill=NEON_GREEN)
        draw.text((92, 460), "When...", font=get_font("bold", 17), fill=PAPER_BG)
        draw.text((480, 460), "Telegram bots", font=get_font("bold", 17), fill=PAPER_BG)
        draw.text((820, 460), "Manual trading", font=get_font("bold", 17), fill=PAPER_BG)
        draw.text((1150, 460), "PulseTrail (Base + Reactive)", font=get_font("bold", 17), fill=INK)

        why_rows = [
            ("You sleep through a 3 AM pump", "Server may crash", "Missed completely", "Secured near the peak"),
            ("A normal 5% wick hits", "Sells you at a loss", "You panic sell", "Cushion widens automatically"),
            ("Price pulls back after 2x", "Dumps 100% at once", "You freeze up", "Locks 40%, rest rides"),
            ("Who holds your funds", "Often holds your key", "You (manual)", "You, via non-custodial vault"),
        ]
        for idx, (w_when, w_bot, w_man, w_pt) in enumerate(why_rows):
            ry = 504 + idx * 62
            draw.rectangle((1120, ry - 2, 1533, ry + 58), fill=(220, 252, 231))
            if hi_row == idx + 1:
                draw.rectangle((67, ry - 2, 1533, ry + 58), outline=GREEN, width=3)
            draw.text((92, ry + 16), w_when, font=get_font("bold", 16), fill=INK)
            draw.text((480, ry + 16), w_bot, font=get_font("sans", 16), fill=RED)
            draw.text((820, ry + 16), w_man, font=get_font("sans", 16), fill=MUTED)
            draw_check_icon(draw, 1146, ry + 26, size=12, color=GREEN, width=3)
            draw.text((1166, ry + 16), w_pt, font=get_font("bold", 16), fill=(6, 95, 70))
            if idx < 3:
                draw.line((67, ry + 58, 1533, ry + 58), fill=DOT_COL, width=2)

    elif scene["route"] == "app":
        _, is_pro, sel_tok, amt_focus, typed_amt, sel_preset, wiggle_on, btn_state, btn_pressed, c1_ok, c2_ok, c3_ok, c_hi = key
        draw.text((64, 92), "Protect my tokens", font=get_font("display", 38), fill=INK)
        draw.text((64, 140), "Pick a token and a strategy. The chart and estimator show how it behaves.", font=get_font("sans", 17), fill=MUTED)

        draw_neo_card(draw, (64, 178, 910, 875), fill=CARD_BG, outline=INK, width=3, radius=20, shadow_offset=(6, 7))

        draw.rounded_rectangle((92, 200, 260, 240), radius=10, fill=CARD_BG, outline=INK, width=3)
        if not is_pro:
            draw.rounded_rectangle((92, 200, 178, 240), radius=8, fill=INK)
            draw.text((112, 209), "Simple", font=get_font("bold", 15), fill=PAPER_BG)
            draw.text((202, 209), "Pro", font=get_font("bold", 15), fill=INK)
        else:
            draw.rounded_rectangle((178, 200, 260, 240), radius=8, fill=INK)
            draw.text((112, 209), "Simple", font=get_font("bold", 15), fill=INK)
            draw.text((204, 209), "Pro", font=get_font("bold", 15), fill=PAPER_BG)

        draw.text((92, 256), "1 · Token to protect", font=get_font("mono_bold", 14), fill=INK)
        toks = ["PTRAIL", "WETH", "BRETT", "DEGEN", "TOSHI"]
        tx = 92
        for t_sym in toks:
            active_t = t_sym == sel_tok
            bg_t = INK if active_t else CARD_BG
            fg_t = PAPER_BG if active_t else INK
            w_t, _ = draw_pill(draw, tx, 282, t_sym, bg=bg_t, fg=fg_t, dot_col=NEON_GREEN if active_t else None, font_size=14, pad_x=16, pad_y=7)
            tx += w_t + 10

        draw.rounded_rectangle((92, 332, 882, 372), radius=10, fill=PAPER_BG, outline=INK, width=2)
        draw.text((108, 343), "0x43613f719a59D8484ABDF416ecea590D397e1058 (PTRAIL / dUSDC Pool Verified)", font=get_font("mono", 13), fill=MUTED)

        draw.text((92, 388), "Amount", font=get_font("mono_bold", 14), fill=INK)
        draw.text((695, 388), f"Balance: 25,000 {sel_tok}", font=get_font("mono_bold", 13), fill=MUTED)
        draw.rounded_rectangle((92, 412, 882, 462), radius=12, fill=CARD_BG, outline=PURPLE if amt_focus else INK, width=3)
        draw.text((110, 424), typed_amt, font=get_font("mono_bold", 21), fill=INK if typed_amt != "0.0" else MUTED)

        for idx, pct_lbl in enumerate(["25%", "50%", "MAX"]):
            draw_pill(draw, 92 + idx * 74, 472, pct_lbl, bg=CARD_BG, fg=INK, font_size=12, pad_x=12, pad_y=4)

        draw.text((92, 514), "2 · Strategy", font=get_font("mono_bold", 14), fill=INK)
        presets = [
            ("rocket", "Meme coin rocket", "Starts at +15% with a wide", "12% buffer. Lets runners run."),
            ("safe", "Conservative lock", "Starts at +8% with a tight", "5% buffer. Locks early gains."),
            ("moon", "Risk-free moonbag", "Starts at +30% with default", "8/6/5% buffers."),
        ]
        pw = 254
        for idx, (pk, pname, p1, p2) in enumerate(presets):
            px0 = 92 + idx * (pw + 14)
            py0 = 540
            is_sel = pk == sel_preset
            bg_p = NEON_GREEN if is_sel else CARD_BG
            if is_sel:
                draw.rounded_rectangle((px0 + 4, py0 + 4, px0 + pw + 4, py0 + 96 + 4), radius=14, fill=INK)
            draw.rounded_rectangle((px0, py0, px0 + pw, py0 + 96), radius=14, fill=bg_p, outline=INK, width=3)
            draw.text((px0 + 12, py0 + 10), pname, font=get_font("bold", 15), fill=INK)
            draw.text((px0 + 12, py0 + 36), p1, font=get_font("sans", 13), fill=INK if is_sel else MUTED)
            draw.text((px0 + 12, py0 + 54), p2, font=get_font("sans", 13), fill=INK if is_sel else MUTED)

        draw.rounded_rectangle((92, 652, 882, 756), radius=14, fill=PAPER_BG, outline=INK, width=2)
        buf_txt = "12% -> 9% -> 7%" if sel_preset == "rocket" else "5% -> 4% -> 3%"
        act_txt = "+15%" if sel_preset == "rocket" else "+8%"
        draw.text((110, 662), f"Start trailing after gain: {act_txt}   |   Step 1-3 Buffers: {buf_txt}", font=get_font("mono_bold", 13), fill=INK)
        cb_box = (110, 696, 136, 722)
        draw.rounded_rectangle(cb_box, radius=6, fill=NEON_GREEN if wiggle_on else CARD_BG, outline=INK, width=3)
        if wiggle_on:
            draw_check_icon(draw, 123, 709, size=14, color=INK, width=3)
        draw.text((148, 698), "Smart wiggle room (adds up to +10% buffer in wild volatility swings)", font=get_font("bold", 15), fill=INK)
        if wiggle_on:
            draw_pill(draw, 148, 724, "8-Tick Rolling Volatility Buffer Active (12% -> 22% max)", bg=(220, 252, 231), fg=(6, 95, 70), check_col=(6, 95, 70), font_size=11, pad_x=10, pad_y=2)

        btn_txt = "Activate auto-protection"
        btn_bg = RED
        has_chk = False
        if btn_state == "approving":
            btn_txt = "Approve in your wallet..."
            btn_bg = (185, 28, 28)
        elif btn_state == "creating":
            btn_txt = "Creating protection on Base..."
            btn_bg = (185, 28, 28)
        elif btn_state == "active":
            btn_txt = "Protection Active (Position #1)"
            btn_bg = GREEN
            has_chk = True
        draw_button(draw, (92, 778, 882, 844), btn_txt, bg=btn_bg, fg=(255, 255, 255), font_size=20, pressed=btn_pressed, has_check=has_chk)

        # Right Column: RiskShield + Estimator
        draw_neo_card(draw, (946, 178, 1536, 490), fill=CARD_BG, outline=INK, width=3, radius=20, shadow_offset=(6, 7))
        draw.text((976, 204), "Safety check", font=get_font("bold", 22), fill=INK)
        draw_pill(draw, 1132, 204, sel_tok, bg=PAPER_BG, fg=INK, font_size=13)

        checks = [
            (c1_ok, "Honeypot shield: this token can be sold safely", c_hi == 1),
            (c2_ok, "Pool depth: your trade is 0.42% of the pool (<5%)", c_hi == 2),
            (c3_ok, "Pool health: reserves are healthy ($2.4M liquidity)", c_hi == 3),
        ]
        for idx, (ok, c_txt, is_hi) in enumerate(checks):
            cy = 262 + idx * 66
            if is_hi:
                draw.rounded_rectangle((968, cy - 8, 1514, cy + 44), radius=10, fill=(220, 252, 231), outline=GREEN, width=2)
            draw.rounded_rectangle((978, cy, 1008, cy + 30), radius=7, fill=NEON_GREEN if ok else DOT_COL, outline=INK, width=2)
            if ok:
                draw_check_icon(draw, 993, cy + 15, size=12, color=INK, width=3)
            draw.text((1022, cy + 4), c_txt, font=get_font("sans", 16), fill=INK)
            if idx < 2:
                draw.line((978, cy + 48, 1506, cy + 48), fill=DOT_COL, width=2)

        draw_neo_card(draw, (946, 520, 1536, 875), fill=CARD_BG, outline=INK, width=3, radius=20, shadow_offset=(6, 7))
        draw.text((976, 546), "What you would get", font=get_font("bold", 22), fill=INK)
        draw.text((976, 578), "Per $1,000 protected on the demo path after 0.30% swap fee.", font=get_font("sans", 14), fill=MUTED)
        draw.text((976, 598), "0.00% PulseTrail protocol fee.", font=get_font("mono_bold", 13), fill=GREEN)

        if sel_preset == "rocket":
            est_rows = [
                ("Step 1 cash-out (40% sold @ $1.76)", "$702 USDC"),
                ("Step 2 cash-out (30% sold @ $1.60)", "$479 USDC"),
                ("Step 3 cash-out (30% sold @ $1.47)", "$440 USDC"),
            ]
            tot_str = "~$1,621 (+62%)"
        else:
            est_rows = [
                ("Step 1 cash-out (40% sold @ $1.88)", "$750 USDC"),
                ("Step 2 cash-out (30% sold @ $1.80)", "$538 USDC"),
                ("Step 3 cash-out (30% sold @ $1.74)", "$520 USDC"),
            ]
            tot_str = "~$1,808 (+81%)"

        for idx, (rl, rv) in enumerate(est_rows):
            ry = 638 + idx * 44
            draw.text((976, ry), rl, font=get_font("mono", 14), fill=INK)
            draw.text((1400, ry), rv, font=get_font("mono_bold", 15), fill=INK)
            draw.line((976, ry + 32, 1506, ry + 32), fill=DOT_COL, width=1)

        draw.line((976, 784, 1506, 784), fill=INK, width=3)
        draw.text((976, 802), "Estimated total return", font=get_font("bold", 19), fill=INK)
        draw.text((1315, 800), tot_str, font=get_font("mono_bold", 21), fill=GREEN)

    elif scene["route"] == "positions":
        _, step1_done, cur_hwm, copied, copy_pressed = key
        draw.text((64, 92), "My positions", font=get_font("display", 38), fill=INK)
        draw.text((64, 140), "Loaded straight from the Base Mainnet vault contract (0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde).", font=get_font("sans", 17), fill=MUTED)

        draw_neo_card(draw, (64, 184, 860, 855), fill=CARD_BG, outline=INK, width=4, radius=22, shadow_offset=(7, 9))
        draw.text((98, 214), "PTRAIL", font=get_font("display", 32), fill=INK)
        draw.text((230, 218), "#1", font=get_font("mono_bold", 26), fill=MUTED)
        draw_pill(draw, 685, 216, "Protecting", bg=(220, 252, 231), fg=(6, 95, 70), dot_col=(31, 191, 75), font_size=14)

        held_pct = 60 if step1_done else 100
        banked_usdc = "552.00 USDC" if step1_done else "0.00 USDC"

        draw.text((98, 268), f"Protecting 10,000 PTRAIL  ·  {held_pct}% still held in vault", font=get_font("mono_bold", 16), fill=MUTED)

        draw.rounded_rectangle((98, 308, 826, 382), radius=14, fill=PAPER_BG, outline=INK, width=2)
        draw.text((120, 322), "Entry: $1.000", font=get_font("mono_bold", 15), fill=INK)
        draw.text((345, 322), "Activation: $1.150 (+15%)", font=get_font("mono_bold", 15), fill=PURPLE)
        draw.text((615, 322), f"Peak: ${cur_hwm:.2f} (+{int((cur_hwm-1)*100)}%)", font=get_font("mono_bold", 15), fill=(195, 115, 0))
        draw.text((120, 350), "Adaptive Trail: 12% + 6.4% vol wiggle = 18.4% effective buffer", font=get_font("mono", 13), fill=MUTED)

        draw.rounded_rectangle((98, 400, 826, 458), radius=12, fill=(220, 252, 231) if step1_done else PAPER_BG, outline=GREEN if step1_done else INK, width=2)
        draw.text((120, 417), f"Banked Proceeds:  {banked_usdc}  (sent directly to 0x71C...89A)", font=get_font("mono_bold", 17), fill=(6, 95, 70) if step1_done else INK)

        st_active = 2 if step1_done else 1
        steps_pos = [
            ("Monitoring", "Cleared +15% hurdle"),
            ("Step 1: 40%", "Sold @ $1.38 (+$552)" if step1_done else f"Trailing peak ${cur_hwm:.2f}"),
            ("Step 2: 30%", f"Trailing peak ${cur_hwm:.2f}" if step1_done else "Sells 30% next"),
            ("Step 3: 30%", "Sells the last 30%"),
        ]
        sw = 172
        for n, (st_t, st_s) in enumerate(steps_pos):
            sx0 = 98 + n * (sw + 12)
            sy0 = 480
            is_cur = n == st_active
            is_done = n < st_active
            bg_c = NEON_GREEN if is_cur else ((220, 252, 231) if is_done else PAPER_BG)
            if is_cur:
                draw.rounded_rectangle((sx0 + 3, sy0 + 4, sx0 + sw + 3, sy0 + 74), radius=12, fill=INK)
            draw.rounded_rectangle((sx0, sy0, sx0 + sw, sy0 + 70), radius=12, fill=bg_c, outline=INK, width=2)
            tx_lbl = sx0 + 10
            if is_done:
                draw_check_icon(draw, sx0 + 16, sy0 + 20, size=10, color=GREEN, width=3)
                tx_lbl += 16
            draw.text((tx_lbl, sy0 + 10), st_t, font=get_font("bold", 14), fill=INK)
            draw.text((sx0 + 10, sy0 + 36), st_s, font=get_font("mono", 12), fill=INK if is_cur else MUTED)

        draw_button(draw, (98, 574, 365, 620), "Cancel and withdraw tokens", bg=INK, fg=PAPER_BG, font_size=14, pressed=False)

        draw.line((98, 644, 826, 644), fill=DOT_COL, width=2)
        draw.text((98, 660), "SHARE SHIELDED POSITION", font=get_font("mono_bold", 12), fill=MUTED)
        draw.text((725, 660), "1-Click Viral", font=get_font("mono_bold", 12), fill=PURPLE)

        draw_button(draw, (98, 688, 250, 732), "Farcaster", bg=(138, 99, 210), fg=(255, 255, 255), font_size=14, radius=9)
        draw_button(draw, (266, 688, 418, 732), "Twitter / X", bg=INK, fg=(255, 255, 255), font_size=14, radius=9)
        draw_button(
            draw,
            (434, 688, 595, 732),
            "Copied!" if copied else "Copy Proof",
            bg=NEON_GREEN if copied else CARD_BG,
            fg=INK,
            font_size=14,
            pressed=copy_pressed,
            radius=9,
            has_check=copied,
        )

        draw.rounded_rectangle((98, 750, 826, 828), radius=10, fill=PAPER_BG, outline=DOT_COL, width=2)
        draw.text((114, 762), '"Just secured 10,000 $PTRAIL with an autonomous volatility-adaptive', font=get_font("mono", 12), fill=MUTED)
        draw.text((114, 784), 'trailing stop on @base powered by @reactive_net. 0 keys shared. #PulseTrail"', font=get_font("mono", 12), fill=MUTED)

        draw_neo_card(draw, (896, 184, 1536, 855), fill=CARD_BG, outline=INK, width=3, radius=22, shadow_offset=(6, 8))
        draw.text((928, 214), "Reactive Brain Telemetry (Chain 1597)", font=get_font("bold", 21), fill=INK)
        draw_pill(draw, 928, 252, "Contract: 0x43613f719a59D8484ABDF416ecea590D397e1058", bg=PAPER_BG, fg=INK, font_size=12)

        logs = [
            ("[Block #8787939]", "Subscribed to Base Pair 0x1B2b...3394 Sync(r0,r1)", GREEN),
            ("[Tick #18]", "Spot $1.18 >= Activation $1.15 -> Advance Stage 0 -> 1", PURPLE),
            ("[Tick #39]", "New High-Water Mark Ratcheted: $1.84 (+84.0%)", AMBER),
            ("[Tick #44]", "8-Tick Volatility sigma = 640 bps -> Trail widened to 18.4%", INK),
            ("[Tick #51]", "Pullback to $1.38 -> Emit Callback(8453, 350k gas)", RED),
            ("[Base #55615890]", "executeStageExit: 4,000 PTRAIL swapped -> +552 USDC", GREEN),
        ]
        for idx, (blk, msg, col) in enumerate(logs):
            ly = 308 + idx * 82
            draw.rounded_rectangle((928, ly, 1504, ly + 68), radius=12, fill=PAPER_BG, outline=INK, width=2)
            draw.text((944, ly + 10), blk, font=get_font("mono_bold", 13), fill=col)
            draw.text((944, ly + 34), msg, font=get_font("mono", 13), fill=INK)

    elif scene["route"] == "proof":
        draw.text((64, 92), "Checked on chain", font=get_font("display", 38), fill=INK)
        draw.text((64, 140), "Everything a judge or careful trader needs to verify on BaseScan & ReactScan.", font=get_font("sans", 17), fill=MUTED)

        stat_cards = [
            ("2.0s", "Base to Reactive and back (1.0s each way)", NEON_GREEN),
            ("0.00%", "PulseTrail fee. Only 0.30% pool fee & gas apply.", CARD_BG),
            ("0 keys", "Held by PulseTrail. 100% non-custodial vault.", CARD_BG),
        ]
        cw = 468
        for idx, (big_v, sub_v, bg_c) in enumerate(stat_cards):
            cx0 = 64 + idx * (cw + 34)
            draw_neo_card(draw, (cx0, 182, cx0 + cw, 304), fill=bg_c, outline=INK, width=3, radius=20, shadow_offset=(5, 6))
            draw.text((cx0 + 28, 198), big_v, font=get_font("display", 44), fill=INK)
            draw.text((cx0 + 28, 258), sub_v, font=get_font("sans", 15), fill=INK if bg_c != CARD_BG else MUTED)

        draw.text((64, 330), "Benchmarked Cross-Chain Protection Loop (T0 -> T1 -> T2)", font=get_font("bold", 22), fill=INK)
        draw_neo_card(draw, (64, 368, 1536, 624), fill=CARD_BG, outline=INK, width=3, radius=18, shadow_offset=(5, 6))
        draw.rounded_rectangle((64, 368, 1536, 418), radius=16, fill=INK)
        headers = [("Phase", 88), ("Network", 340), ("Action / Event", 620), ("Offset", 1060), ("Latency", 1220), ("Status", 1390)]
        for h_txt, hx in headers:
            draw.text((hx, 383), h_txt, font=get_font("bold", 15), fill=PAPER_BG)

        bench_rows = [
            ("0. Setup & Escrow", "Base Mainnet (8453)", "PositionRegistered (posId 1)", "T0 - 12s", "Baseline", "Verified"),
            ("1. Origin Pullback (T0)", "Base Mainnet (8453)", "Sync ($1.50 -> $1.32 dip)", "T0 (0.0s)", "Trigger Tick", "Verified"),
            ("2. ReactVM Brain (T1)", "Reactive Mainnet (1597)", "StageTriggered -> Callback(350k)", "T0 + 1.0s", "dT = 1.00s", "Verified"),
            ("3. Destination Swap (T2)", "Base Mainnet (8453)", "executeStageExit (40% -> USDC)", "T0 + 2.0s", "Total: 2.00s", "Verified"),
        ]
        for idx, r_vals in enumerate(bench_rows):
            ry = 424 + idx * 48
            if idx == 3:
                draw.rectangle((67, ry - 2, 1533, ry + 44), fill=(220, 252, 231))
            cols_x = [88, 340, 620, 1060, 1220, 1390]
            for c_i, val in enumerate(r_vals):
                f_use = get_font("mono_bold", 14) if c_i in (2, 3, 4) else get_font("sans", 15)
                c_fill = GREEN if c_i == 4 else INK
                draw.text((cols_x[c_i], ry + 10), val, font=f_use, fill=c_fill)
            if idx < 3:
                draw.line((67, ry + 45, 1533, ry + 45), fill=DOT_COL, width=2)

        draw.text((64, 646), "Verified Live Mainnet Contracts", font=get_font("bold", 20), fill=INK)
        draw_neo_card(draw, (64, 680, 1536, 868), fill=CARD_BG, outline=INK, width=3, radius=18, shadow_offset=(5, 6))
        contracts = [
            ("Vault & Executor (Base 8453)", "PulseTrailCallback.sol", "0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde", "BaseScan ->"),
            ("Reactive Brain (Reactive 1597)", "PulseTrailReactive.sol", "0x43613f719a59D8484ABDF416ecea590D397e1058", "ReactScan ->"),
            ("Official Callback Proxy (Base 8453)", "Reactive Proxy", "0x0D3E76De6bC44309083cAAFdB49A088B8a250947", "BaseScan ->"),
            ("Monitored Pool (Base 8453)", "PTRAIL / dUSDC Pair", "0x1B2b40430FB0263c7BA25cf4B4FF9462c9153394", "BaseScan ->"),
        ]
        for idx, (cname, csol, caddr, cexp) in enumerate(contracts):
            ry = 692 + idx * 42
            draw.text((88, ry + 6), cname, font=get_font("bold", 14), fill=INK)
            draw.text((430, ry + 6), csol, font=get_font("mono", 14), fill=MUTED)
            draw.text((730, ry + 6), caddr, font=get_font("mono_bold", 14), fill=INK)
            draw.text((1380, ry + 6), cexp, font=get_font("mono_bold", 14), fill=GREEN)
            if idx < 3:
                draw.line((67, ry + 38, 1533, ry + 38), fill=DOT_COL, width=1)

    _PAGE_CACHE["key"] = key
    _PAGE_CACHE["img"] = page.copy()
    return page

# ==============================================================================
# 4. CAMERA & CURSOR CHOREOGRAPHY ACROSS 2:36 (4,680 FRAMES)
# ==============================================================================
CLICK_FRAMES = [560, 1600, 1680, 1740, 1800, 1860, 2130, 2220, 2920, 3010, 3310, 3990]

def get_cursor_state(frame, scene):
    click_age = None
    for cf in CLICK_FRAMES:
        if 0 <= frame - cf <= 18:
            click_age = frame - cf
            break

    sid = scene["id"]
    if sid == "hero_intro":
        if frame < 420:
            x = interp(frame, 250, 400, 620, 320)
            y = interp(frame, 250, 400, 360, 645)
        else:
            x = interp(frame, 420, 558, 320, 190)
            y = interp(frame, 420, 558, 645, 528)
    elif sid == "simulate":
        x = interp(frame, 600, 720, 190, 1180)
        y = interp(frame, 600, 720, 528, 460)
    elif sid == "why_compare":
        x = interp(frame, 1140, 1450, 520, 1260)
        y = interp(frame, 1140, 1450, 260, 650)
    elif sid == "configure_token":
        if frame < 1600:
            x = interp(frame, 1560, 1600, 800, 565)
            y = interp(frame, 1560, 1600, 300, 34)
        elif frame < 1680:
            x = interp(frame, 1600, 1680, 565, 215)
            y = interp(frame, 1600, 1680, 34, 298)
        elif frame < 1740:
            x = interp(frame, 1680, 1740, 215, 295)
            y = interp(frame, 1680, 1740, 298, 298)
        elif frame < 1800:
            x = interp(frame, 1740, 1800, 295, 130)
            y = interp(frame, 1740, 1800, 298, 298)
        else:
            x = interp(frame, 1800, 1860, 130, 280)
            y = interp(frame, 1800, 1860, 298, 436)
    elif sid == "configure_preset":
        if frame < 2130:
            x = interp(frame, 2040, 2130, 280, 480)
            y = interp(frame, 2040, 2130, 436, 588)
        elif frame < 2220:
            x = interp(frame, 2130, 2220, 480, 210)
            y = interp(frame, 2130, 2220, 588, 588)
        else:
            x = interp(frame, 2230, 2320, 210, 1220)
            y = interp(frame, 2230, 2320, 588, 700)
    elif sid == "shield_checks":
        x = interp(frame, 2460, 2750, 1180, 1180)
        y = interp(frame, 2460, 2750, 275, 410)
    elif sid == "shield_wiggle":
        if frame < 2920:
            x = interp(frame, 2880, 2920, 1180, 218)
            y = interp(frame, 2880, 2920, 410, 220)
        else:
            x = interp(frame, 2925, 3010, 218, 123)
            y = interp(frame, 2925, 3010, 220, 709)
    elif sid == "vault":
        x = interp(frame, 3240, 3310, 300, 480)
        y = interp(frame, 3240, 3310, 709, 810)
    elif sid == "inspect":
        if frame < 3940:
            x = interp(frame, 3660, 3840, 480, 510)
            y = interp(frame, 3660, 3840, 420, 515)
        else:
            x = interp(frame, 3940, 3990, 510, 512)
            y = interp(frame, 3940, 3990, 515, 710)
    else:
        x = interp(frame, 4140, 4320, 600, 1260)
        y = interp(frame, 4140, 4320, 300, 560)

    return int(x), int(y), click_age

def get_camera_state(frame, scene, is_vertical=False):
    sid = scene["id"]
    if sid == "hero_intro":
        z = interp(frame, 240, 320, 1.0, 1.12 if is_vertical else 1.16)
        cx = interp(frame, 240, 520, 410 if is_vertical else 680, 410 if is_vertical else 580)
        cy = interp(frame, 240, 520, 420, 460)
        return z, cx, cy
    elif sid == "simulate":
        z = interp(frame, 600, 650, 1.12 if is_vertical else 1.16, 1.15 if is_vertical else 1.28)
        cx = interp(frame, 600, 650, 410 if is_vertical else 580, 1148 if is_vertical else 1110)
        cy = interp(frame, 600, 650, 460, 475)
        if frame > 1090:
            z = interp(frame, 1090, 1139, 1.15 if is_vertical else 1.28, 1.0)
            cx = interp(frame, 1090, 1139, 1148 if is_vertical else 1110, 800)
        return z, cx, cy
    elif sid == "why_compare":
        if frame < 1260:
            z = 1.04 if is_vertical else 1.04
            cx = 800
            cy = interp(frame, 1140, 1240, 340, 480)
        else:
            z = interp(frame, 1260, 1320, 1.04, 1.08 if is_vertical else 1.06)
            cx = 1040 if is_vertical else 800
            cy = 520
        return z, cx, cy
    elif sid == "configure_token":
        z = interp(frame, 1600, 1650, 1.0, 1.08 if is_vertical else 1.22)
        cx = interp(frame, 1600, 1650, 800, 485 if is_vertical else 520)
        cy = interp(frame, 1600, 1650, 460, 420)
        return z, cx, cy
    elif sid == "configure_preset":
        if frame < 2260:
            z = 1.08 if is_vertical else 1.22
            cx = 485 if is_vertical else 520
            cy = 540
        else:
            z = interp(frame, 2260, 2310, 1.08 if is_vertical else 1.22, 1.12 if is_vertical else 1.24)
            cx = interp(frame, 2260, 2310, 485 if is_vertical else 520, 1240 if is_vertical else 1120)
            cy = interp(frame, 2260, 2310, 540, 680 if is_vertical else 640)
        return z, cx, cy
    elif sid == "shield_checks":
        z = interp(frame, 2460, 2510, 1.12 if is_vertical else 1.24, 1.22 if is_vertical else 1.32)
        cx = 1240 if is_vertical else 1180
        cy = interp(frame, 2460, 2510, 640, 360)
        return z, cx, cy
    elif sid == "shield_wiggle":
        z = interp(frame, 2880, 2930, 1.22 if is_vertical else 1.32, 1.08 if is_vertical else 1.24)
        cx = interp(frame, 2880, 2930, 1240 if is_vertical else 1180, 485 if is_vertical else 520)
        cy = interp(frame, 2880, 2930, 360, 550)
        return z, cx, cy
    elif sid == "vault":
        z = 1.08 if is_vertical else 1.14
        cx = 485 if is_vertical else 680
        cy = 570 if is_vertical else 520
        return z, cx, cy
    elif sid == "inspect":
        if frame < 3820:
            z = interp(frame, 3660, 3710, 1.0, 1.10 if is_vertical else 1.18)
            cx = interp(frame, 3660, 3710, 800, 462 if is_vertical else 580)
            cy = interp(frame, 3660, 3710, 460, 500)
        elif frame < 3930:
            z = 1.10 if is_vertical else 1.18
            cx = interp(frame, 3820, 3860, 462 if is_vertical else 580, 1210 if is_vertical else 1020)
            cy = 500
        else:
            z = 1.10 if is_vertical else 1.18
            cx = interp(frame, 3930, 3970, 1210 if is_vertical else 1020, 462 if is_vertical else 580)
            cy = 540
        return z, cx, cy
    elif sid == "proof":
        z = 1.0 if is_vertical else 1.08
        cx = 640 if is_vertical else 800
        cy = 480
        return z, cx, cy
    return 1.0, 800, 460

# ==============================================================================
# 5. OVERLAY CARDS (Cover Card on Frame 0, Side Captions, Test It Yourself Modal)
# ==============================================================================
def draw_cover_card(canvas, draw, frame, is_vertical=False):
    W, H = canvas.size
    cw = int(W * (0.90 if is_vertical else 0.74))
    ch = int(H * (0.50 if is_vertical else 0.62))
    x0 = (W - cw) // 2
    y0 = (H - ch) // 2 - (40 if not is_vertical else 60)

    draw.rounded_rectangle((x0 + 14, y0 + 18, x0 + cw + 14, y0 + ch + 18), radius=16, fill=(0, 0, 0))
    draw.rounded_rectangle((x0, y0, x0 + cw, y0 + ch), radius=16, fill=PAPER_BG, outline=INK, width=4)

    for py in range(y0 + 20, y0 + ch - 20, 22):
        for px in range(x0 + 20, x0 + cw - 20, 22):
            draw.rectangle((px, py, px + 1, py + 1), fill=DOT_COL)

    tw, th = 130, 32
    tx0 = W // 2 - tw // 2
    ty0 = y0 - 16
    draw.rounded_rectangle((tx0, ty0, tx0 + tw, ty0 + th), radius=4, fill=(238, 235, 222), outline=(205, 200, 185), width=2)

    pad = 50 if is_vertical else 72
    logo_sz = 84 if is_vertical else 104
    logo = get_logo(logo_sz)
    canvas.paste(logo, (x0 + pad, y0 + pad + 6), logo)

    title_f = get_font("display", 70 if is_vertical else 100)
    draw.text((x0 + pad + logo_sz + 26, y0 + pad - 6), "PULSETRAIL", font=title_f, fill=INK)

    bx = x0 + cw - pad - 118
    by = y0 + pad + 18
    draw.rounded_rectangle((bx + 4, by + 4, bx + 114, by + 50), radius=10, fill=INK)
    draw.rounded_rectangle((bx, by, bx + 110, by + 46), radius=10, fill=NEON_GREEN, outline=INK, width=3)
    draw.text((bx + 22, by + 9), "BASE", font=get_font("mono_bold", 24), fill=INK)

    tag_y = y0 + pad + logo_sz + 32
    tag_f = get_font("sans", 26 if is_vertical else 31)
    draw.text((x0 + pad, tag_y), "Autonomous smart stop-losses for Base that ratchet up", font=tag_f, fill=MUTED)
    draw.text((x0 + pad, tag_y + (36 if is_vertical else 42)), "and cash out into USDC in 3 steps.", font=tag_f, fill=INK)

    strip_y = tag_y + (96 if is_vertical else 104)
    steps_cov = [
        ("1. PROTECT", "Pick token & 3-step strategy"),
        ("2. RATCHET", "Reactive Brain trails peaks"),
        ("3. CASH OUT", "40/30/30% swapped to USDC"),
    ]
    sc_w = (cw - pad * 2 - 32) // 3
    for idx, (st_h, st_p) in enumerate(steps_cov):
        sx = x0 + pad + idx * (sc_w + 16)
        draw.rounded_rectangle((sx + 3, strip_y + 3, sx + sc_w + 3, strip_y + 84 + 3), radius=12, fill=INK)
        draw.rounded_rectangle((sx, strip_y, sx + sc_w, strip_y + 84), radius=12, fill=CARD_BG, outline=INK, width=2)
        draw.text((sx + 14, strip_y + 12), st_h, font=get_font("mono_bold", 14 if is_vertical else 16), fill=GREEN if idx == 2 else INK)
        draw.text((sx + 14, strip_y + 42), st_p, font=get_font("sans", 13 if is_vertical else 16), fill=MUTED)

    by_pills = y0 + ch - (128 if is_vertical else 88)
    pills = [
        ("BASE MAINNET · 8453", INK, CARD_BG),
        ("REACTIVE BRAIN · 1597", PURPLE, CARD_BG),
        ("SUB-2.0S LOOP", GREEN, (220, 252, 231)),
    ]
    px_cur = x0 + pad
    for p_txt, p_col, p_bg in pills:
        f_p = get_font("mono_bold", 14 if is_vertical else 16)
        bb = draw.textbbox((0, 0), p_txt, font=f_p)
        pw = bb[2] - bb[0] + 28
        ph = 40
        draw.rounded_rectangle((px_cur, by_pills, px_cur + pw, by_pills + ph), radius=6, fill=p_bg, outline=p_col, width=3)
        draw.text((px_cur + 14, by_pills + 9), p_txt, font=f_p, fill=p_col)
        px_cur += pw + 14

    note_y = by_pills + 52 if is_vertical else by_pills + 4
    note_x = x0 + pad if is_vertical else px_cur + 18
    draw.text((note_x, note_y), "a walkthrough of the live app", font=get_font("script", 27 if is_vertical else 29), fill=BLUE_NOTE)

def draw_outro_modal(canvas, draw, frame, is_vertical=False):
    W, H = canvas.size
    prog = ease_out_cubic((frame - 4440) / 18.0)
    mw = int(W * (0.92 if is_vertical else 0.78))
    mh = int(H * (0.64 if is_vertical else 0.65))
    mx0 = (W - mw) // 2
    my0 = int((H - mh) // 2 - (30 if not is_vertical else 40) + (1.0 - prog) * 40)

    overlay = Image.new("RGBA", (W, H), (10, 12, 18, int(160 * prog)))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB"), (0, 0))
    draw = ImageDraw.Draw(canvas)

    draw_neo_card(draw, (mx0, my0, mx0 + mw, my0 + mh), fill=CARD_BG, outline=INK, width=4, radius=18, shadow_offset=(12, 16), shadow_col=(0, 0, 0))
    tw = 120
    draw.rounded_rectangle((W // 2 - tw // 2, my0 - 14, W // 2 + tw // 2, my0 + 14), radius=4, fill=(238, 235, 222), outline=(205, 200, 185), width=2)

    pad = 36 if is_vertical else 48
    f_head = get_font("display", 38 if is_vertical else 44)
    draw.text((mx0 + pad, my0 + 28), "TEST IT YOURSELF", font=f_head, fill=INK)
    hb = draw.textbbox((mx0 + pad, my0 + 28), "TEST IT YOURSELF", font=f_head)

    if not is_vertical:
        draw.text((hb[2] + 24, my0 + 38), "simulating needs no wallet", font=get_font("script", 26), fill=BLUE_NOTE)
        sy = my0 + 106
    else:
        draw.text((mx0 + pad, hb[3] + 6), "simulating needs no wallet", font=get_font("script", 24), fill=BLUE_NOTE)
        sy = hb[3] + 50

    steps = [
        ("1", "Open pulsetrail.app and press Play a simulated pump"),
        ("2", "Pick PTRAIL, BRETT, or paste any Base token CA in Protect"),
        ("3", "Check Honeypot & Pool Depth Shield — no wallet needed"),
        ("4", "Connect a Base wallet & click Activate auto-protection (~$0.008 gas)"),
        ("5", "Verify live callbacks on BaseScan (8453) & ReactScan (1597)"),
    ]

    for num, s_txt in steps:
        draw.ellipse((mx0 + pad, sy, mx0 + pad + 34, sy + 34), fill=BLUE_NOTE)
        draw.text((mx0 + pad + 11, sy + 4), num, font=get_font("bold", 17), fill=(255, 255, 255))
        draw.text((mx0 + pad + 48, sy + 5), s_txt, font=get_font("sans", 17 if is_vertical else 18), fill=INK)
        sy += 50 if is_vertical else 56

    if not is_vertical:
        rx0 = mx0 + int(mw * 0.56)
        rw = mw - int(mw * 0.56) - pad
        ry0 = my0 + 106

        draw.rounded_rectangle((rx0, ry0, rx0 + rw, ry0 + 118), radius=10, fill=(244, 253, 248), outline=GREEN, width=3)
        draw.text((rx0 + 18, ry0 + 14), "VERIFIED ON-CHAIN PROOF & LEDGER", font=get_font("mono_bold", 14), fill=GREEN)
        draw.text((rx0 + 18, ry0 + 40), "pulsetrail.app/#proof", font=get_font("mono_bold", 18), fill=INK)
        draw.text((rx0 + 18, ry0 + 68), "Vault: 0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde", font=get_font("mono", 12), fill=MUTED)
        draw.text((rx0 + 18, ry0 + 88), "Brain: 0x43613f719a59D8484ABDF416ecea590D397e1058", font=get_font("mono", 12), fill=MUTED)

        ty0 = ry0 + 136
        draw.rounded_rectangle((rx0, ty0, rx0 + rw, ty0 + 195), radius=10, fill=(20, 18, 14), outline=INK, width=3)
        draw.text((rx0 + 18, ty0 + 14), "RUN & VERIFY LOCALLY", font=get_font("mono_bold", 14), fill=AMBER)
        cmds = [
            "$ npm install && npm --prefix frontend run dev",
            "$ cp .env.example .env",
            "# BASE_RPC_URL & REACTIVE_RPC_URL configured",
            "$ npm run test            # Forge test suite",
            "$ npm run verify:latency  # 2.00s loop proof",
        ]
        for idx, c_line in enumerate(cmds):
            col = (165, 162, 150) if c_line.startswith("#") else (242, 240, 234)
            draw.text((rx0 + 18, ty0 + 44 + idx * 27), c_line, font=get_font("mono", 14), fill=col)

        by_close = my0 + mh - 66
        draw.line((mx0 + pad, by_close - 12, mx0 + mw - pad, by_close - 12), fill=DOT_COL, width=2)
        logo = get_logo(36)
        canvas.paste(logo, (mx0 + pad, by_close), logo)
        draw.text((mx0 + pad + 48, by_close + 4), "PulseTrail — Ride. Ratchet. Sleep.", font=get_font("display", 22), fill=INK)
        draw_pill(draw, mx0 + mw - pad - 295, by_close + 2, "Launch App -> pulsetrail.app", bg=RED, fg=(255, 255, 255), border=INK, font_size=14)
    else:
        rx0 = mx0 + pad
        rw = mw - pad * 2
        ry0 = sy + 10
        draw.rounded_rectangle((rx0, ry0, rx0 + rw, ry0 + 96), radius=10, fill=(244, 253, 248), outline=GREEN, width=3)
        draw.text((rx0 + 18, ry0 + 12), "VERIFIED PROOF: pulsetrail.app/#proof", font=get_font("mono_bold", 16), fill=GREEN)
        draw.text((rx0 + 18, ry0 + 40), "Base Vault: 0xCacFaA320D05Ab1b96CD48C8e8bafe4E4928fAde", font=get_font("mono", 14), fill=INK)
        draw.text((rx0 + 18, ry0 + 64), "Reactive Brain: 0x43613f719a59D8484ABDF416ecea590D397e1058", font=get_font("mono", 14), fill=INK)

        ty0 = ry0 + 114
        draw.rounded_rectangle((rx0, ty0, rx0 + rw, ty0 + 140), radius=10, fill=(20, 18, 14), outline=INK, width=3)
        draw.text((rx0 + 18, ty0 + 12), "RUN LOCALLY", font=get_font("mono_bold", 14), fill=AMBER)
        for idx, c_line in enumerate(["$ npm install && npm --prefix frontend run dev", "$ npm run test && npm run verify:latency"]):
            draw.text((rx0 + 18, ty0 + 44 + idx * 32), c_line, font=get_font("mono", 15), fill=(242, 240, 234))

        by_close = my0 + mh - 70
        logo = get_logo(40)
        canvas.paste(logo, (rx0, by_close), logo)
        draw.text((rx0 + 52, by_close + 6), "Ride. Ratchet. Sleep.  ·  pulsetrail.app", font=get_font("display", 23), fill=INK)

def draw_step_caption_badge(draw, x0, y0, w, h, scene):
    draw_neo_card(draw, (x0, y0, x0 + w, y0 + h), fill=(17, 24, 39), outline=NEON_GREEN, width=3, radius=16, shadow_offset=(5, 6), shadow_col=(0, 0, 0))
    draw.rounded_rectangle((x0 + 18, y0 + 16, x0 + 62, y0 + 46), radius=8, fill=NEON_GREEN, outline=INK, width=2)
    draw.text((x0 + 27, y0 + 20), scene["num"], font=get_font("mono_bold", 16), fill=INK)
    draw.text((x0 + 74, y0 + 21), scene["label"], font=get_font("mono_bold", 14), fill=NEON_GREEN)
    draw.text((x0 + 18, y0 + 54), scene["headline"], font=get_font("display", 24), fill=(255, 255, 255))
    draw.text((x0 + 18, y0 + 88), scene["sub"], font=get_font("sans", 15), fill=(205, 205, 198))

# ==============================================================================
# 6. MASTER FRAME COMPOSITOR (1920x1080 Desktop & 1080x1920 Vertical)
# ==============================================================================
_STAGE_BG_CACHE = {}
def get_stage_bg(W, H):
    key = (W, H)
    if key in _STAGE_BG_CACHE:
        return _STAGE_BG_CACHE[key].copy()
    bg = Image.new("RGB", (W, H), STAGE_BG)
    draw = ImageDraw.Draw(bg)
    for y in range(0, H, 6):
        draw.line((0, y, W, y), fill=(20, 18, 14), width=1)
    _STAGE_BG_CACHE[key] = bg
    return bg.copy()

def render_frame(frame, W=1920, H=1080):
    is_vertical = H > W
    canvas = get_stage_bg(W, H)
    draw = ImageDraw.Draw(canvas)
    scene = get_scene(frame)
    local_f = frame - scene["start"]
    scene_dur = scene["end"] - scene["start"] + 1

    if scene["id"] == "cover":
        draw_cover_card(canvas, draw, frame, is_vertical=is_vertical)
    else:
        page = render_browser_page(frame, scene)
        cur_x, cur_y, click_age = get_cursor_state(frame, scene)
        draw_pointer_cursor(page, cur_x, cur_y, click_age=click_age)

        zoom, cx, cy = get_camera_state(frame, scene, is_vertical=is_vertical)
        pw, ph = page.size

        if not is_vertical:
            bx0, by0 = 96, 36
            bw, bh = W - 192, H - 156  # 1728 x 924
        else:
            bx0, by0 = 36, 260
            bw, bh = W - 72, 1180      # 1008 x 1180

        bar_h = 50
        view_w, view_h = bw, bh - bar_h
        target_aspect = view_w / float(view_h)

        if not is_vertical:
            crop_w = pw / zoom
            crop_h = ph / zoom
            if crop_w / crop_h > target_aspect:
                crop_w = crop_h * target_aspect
            else:
                crop_h = crop_w / target_aspect
        else:
            crop_w = min(pw, 980.0 / zoom)
            crop_h = crop_w / target_aspect
            if crop_h > ph:
                crop_h = float(ph)
                crop_w = crop_h * target_aspect

        x0 = clamp(cx - crop_w / 2.0, 0, pw - crop_w)
        y0 = clamp(cy - crop_h / 2.0, 0, ph - crop_h)

        cropped = page.crop((int(x0), int(y0), int(x0 + crop_w), int(y0 + crop_h)))
        viewport_img = cropped.resize((view_w, view_h), Image.BILINEAR)

        draw.rounded_rectangle((bx0 + 10, by0 + 14, bx0 + bw + 10, by0 + bh + 14), radius=16, fill=(0, 0, 0))
        draw.rounded_rectangle((bx0 - 3, by0 - 3, bx0 + bw + 3, by0 + bh + 3), radius=16, fill=(48, 46, 40))

        canvas.paste(viewport_img, (bx0, by0 + bar_h))

        # Scene 4 Vault Confirmation Toast drawn directly on browser viewport overlay
        if scene["id"] == "vault" and frame >= 3490:
            slide = ease_out_cubic((frame - 3490) / 18.0)
            tw_toast = min(580, bw - 48)
            tx_toast = bx0 + bw - tw_toast - 24
            ty_toast = by0 + bar_h + int(-90 + 112 * slide)
            draw_neo_card(draw, (tx_toast, ty_toast, tx_toast + tw_toast, ty_toast + 112), fill=(17, 24, 39), outline=NEON_GREEN, width=3, radius=16, shadow_offset=(5, 7), shadow_col=(0, 0, 0))
            draw_check_icon(draw, tx_toast + 26, ty_toast + 26, size=14, color=NEON_GREEN, width=3)
            draw.text((tx_toast + 44, ty_toast + 14), "Position #1 Registered on Base Mainnet (8453)", font=get_font("bold", 16), fill=NEON_GREEN)
            draw.text((tx_toast + 22, ty_toast + 44), "Vault: 0xCacFaA320D05...fAde  ·  Gas: $0.008  ·  200ms Flashblock", font=get_font("mono", 13), fill=(242, 240, 234))
            draw.text((tx_toast + 22, ty_toast + 72), "Reactive Brain (1597) subscribed to Uniswap V2 Sync(r0,r1)", font=get_font("mono", 12), fill=(169, 167, 159))

        draw.rounded_rectangle((bx0, by0, bx0 + bw, by0 + bar_h), radius=14, fill=BROWSER_BAR)
        draw.rectangle((bx0, by0 + bar_h - 14, bx0 + bw, by0 + bar_h), fill=BROWSER_BAR)

        for idx, col in enumerate([(239, 68, 68), (245, 158, 11), (16, 185, 129)]):
            lx = bx0 + 20 + idx * 20
            ly = by0 + 19
            draw.ellipse((lx, ly, lx + 12, ly + 12), fill=col)

        url_w = 245 if is_vertical else 330
        draw.rounded_rectangle((bx0 + 88, by0 + 10, bx0 + 88 + url_w, by0 + 40), radius=7, fill=(38, 37, 33))
        draw_lock_icon(draw, bx0 + 102, by0 + 17)
        draw.text((bx0 + 120, by0 + 16), scene["url"], font=get_font("mono", 13), fill=(215, 212, 202))

        steps_bar = ["SIMULATE", "CONFIGURE", "SHIELD", "VAULT", "INSPECT", "PROOF"]
        sx_cur = bx0 + bw - (595 if is_vertical else 780)
        for idx, s_lbl in enumerate(steps_bar):
            s_num = idx + 1
            is_done = s_num < scene["step"]
            is_cur = s_num == scene["step"]
            pill_w = 90 if is_vertical else 116
            if is_cur:
                draw.rounded_rectangle((sx_cur, by0 + 10, sx_cur + pill_w, by0 + 40), radius=6, fill=(42, 41, 36), outline=(220, 215, 200), width=1)
                draw.line((sx_cur + 4, by0 + 43, sx_cur + pill_w - 4, by0 + 43), fill=AMBER, width=3)
            c_col = AMBER if is_done else ((255, 255, 255) if is_cur else (90, 88, 80))
            draw.ellipse((sx_cur + 8, by0 + 16, sx_cur + 26, by0 + 34), fill=c_col)
            if is_done:
                draw_check_icon(draw, sx_cur + 17, by0 + 25, size=9, color=INK, width=2)
            else:
                draw.text((sx_cur + 13, by0 + 17), str(s_num), font=get_font("mono_bold", 12), fill=INK)
            t_col = (255, 255, 255) if is_cur else ((215, 200, 160) if is_done else (130, 128, 120))
            draw.text((sx_cur + 32, by0 + 18), s_lbl[:6] if is_vertical else s_lbl, font=get_font("mono_bold", 11 if is_vertical else 12), fill=t_col)
            sx_cur += pill_w + (6 if is_vertical else 10)

        if not (scene["id"] == "proof" and frame >= 4440):
            if not is_vertical:
                cap_w, cap_h = 640, 118
                left_side = scene["id"] in ("simulate", "why_compare", "configure_preset", "shield_checks")
                cap_x = bx0 + 26 if left_side else bx0 + bw - cap_w - 26
                cap_y = by0 + bh - cap_h - 22
                draw_step_caption_badge(draw, cap_x, cap_y, cap_w, cap_h, scene)
            else:
                draw_step_caption_badge(draw, 36, 86, W - 72, 142, scene)

        if scene["id"] == "proof" and frame >= 4440:
            draw_outro_modal(canvas, draw, frame, is_vertical=is_vertical)

    # Bottom Progressive Karaoke Subtitles (synced to exact Voiceover audio window)
    words = scene["subtitle"].split(" ")
    vo_offset_f = int((0.12 if scene["id"] == "cover" else 0.22) * FPS)
    vo_dur_f = max(1, int(scene.get("vo_dur", (scene_dur * 0.82) / FPS) * FPS))
    active_word_idx = int(clamp((local_f - vo_offset_f) / float(vo_dur_f)) * len(words))
    sub_font = get_font("bold", 27 if is_vertical else 24)

    max_sub_w = int(W * 0.86)
    lines = []
    cur_line = []
    for idx, w_str in enumerate(words):
        test_str = " ".join([x[1] for x in cur_line] + [w_str])
        bb = draw.textbbox((0, 0), test_str, font=sub_font)
        if bb[2] - bb[0] > max_sub_w and cur_line:
            lines.append(cur_line)
            cur_line = [(idx, w_str)]
        else:
            cur_line.append((idx, w_str))
    if cur_line:
        lines.append(cur_line)

    sub_y0 = H - (290 if is_vertical else 96)
    for l_idx, line_words in enumerate(lines):
        full_line_str = " ".join([w for _, w in line_words])
        bb = draw.textbbox((0, 0), full_line_str, font=sub_font)
        lw = bb[2] - bb[0]
        wx = (W - lw) // 2
        wy = sub_y0 + l_idx * (38 if is_vertical else 34)
        for w_i, w_str in line_words:
            col = (255, 255, 255) if w_i <= active_word_idx else (115, 112, 104)
            draw.text((wx, wy), w_str, font=sub_font, fill=col)
            w_bb = draw.textbbox((0, 0), w_str + " ", font=sub_font)
            wx += w_bb[2] - w_bb[0]

    return canvas

def render_review_frames():
    print("Rendering review frames for 2m36s timeline...")
    img_d = render_frame(1380, 1920, 1080)
    img_d.save(os.path.join(SCRATCH_DIR, "review_why_compare_16x9.jpg"), quality=92)
    print("Saved review_why_compare_16x9.jpg")

def encode_video(out_mp4, wav_path, W, H):
    print(f"Encoding {out_mp4} ({W}x{H} @ {FPS}fps, {TOTAL_FRAMES} frames = {DURATION_SEC}s)...")
    cmd = [
        "ffmpeg",
        "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{W}x{H}",
        "-pix_fmt", "rgb24",
        "-r", str(FPS),
        "-i", "-",
        "-i", wav_path,
        "-c:v", "libx264",
        "-preset", "fast",
        "-crf", "17",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "192k",
        "-shortest",
        "-movflags", "+faststart",
        out_mp4,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
    for f in range(TOTAL_FRAMES):
        img = render_frame(f, W, H)
        proc.stdin.write(img.tobytes())
        if f % 600 == 0 or f == TOTAL_FRAMES - 1:
            print(f"  [{W}x{H}] Frame {f}/{TOTAL_FRAMES} ({int(100*f/TOTAL_FRAMES)}%)")
    proc.stdin.close()
    proc.wait()
    print(f"Finished {out_mp4} (exit code {proc.returncode})")

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    wav_path = os.path.join(os.path.dirname(__file__), "soundtrack.wav")
    if mode in ("audio", "review", "all"):
        print("Synthesizing 2m36s (156.0s) 120 BPM soundtrack + frame-synced UI SFX...")
        generate_soundtrack(wav_path)
    if mode == "review":
        render_review_frames()
    elif mode == "desktop":
        encode_video(os.path.join(ROOT_DIR, "pulsetrail-demo-1920x1080.mp4"), wav_path, 1920, 1080)
    elif mode == "vertical":
        encode_video(os.path.join(ROOT_DIR, "pulsetrail-demo-1080x1920.mp4"), wav_path, 1080, 1920)
    else:
        render_review_frames()
        encode_video(os.path.join(ROOT_DIR, "pulsetrail-demo-1920x1080.mp4"), wav_path, 1920, 1080)
        encode_video(os.path.join(ROOT_DIR, "pulsetrail-demo-1080x1920.mp4"), wav_path, 1080, 1920)
