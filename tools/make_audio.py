#!/usr/bin/env python3
"""Erzeugt alle Klänge für Frostlicht (res://audio/*): Musik, Wind, Lagerfeuer und Effekte.

Alles wird hier per Code synthetisiert – keine fremden Samples, keine Lizenzfragen.
Benötigt: pip install numpy soundfile      (für .ogg; alternativ geht ffmpeg)
Aufruf:   python3 tools/make_audio.py              (alles)
          python3 tools/make_audio.py music        (nur Musik)
          python3 tools/make_audio.py ambience     (nur Wind + Lagerfeuer)
          python3 tools/make_audio.py sfx          (nur Effekte)

Die Musik ist in F-Dur komponiert (langsam, weiche Akkorde mit zusätzlichen Tönen).
Tonart, Tempo, Akkorde und Melodie stehen im Abschnitt "Komposition" und lassen sich leicht ändern.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))
os.makedirs(OUT, exist_ok=True)


# ===================================================================== Grundlagen
def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db(x):
    return 10.0 ** (x / 20.0)


def _apply(x, gain):
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * gain(f), n, axis=-1)


def lowpass(x, fc, order=2):
    return _apply(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return _apply(x, lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def fade_edges(x, a=0.003, r=0.02):
    x = np.array(x, dtype=np.float64)
    na = min(x.shape[-1] // 2, max(1, int(a * SR)))
    nr = min(x.shape[-1] // 2, max(1, int(r * SR)))
    x[..., :na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    x[..., -nr:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return x


def note_env(n, a=0.005, tau=1.0, r=0.05):
    t = np.arange(n) / SR
    e = np.exp(-t / tau)
    na = min(n // 2, max(1, int(a * SR)))
    nr = min(n // 2, max(1, int(r * SR)))
    e[:na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    e[-nr:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return e


def place(buf, sig, t0, gain=1.0):
    """Mischt sig ab t0 (Sekunden) in buf (mono oder stereo), ohne Umbruch."""
    s = int(round(t0 * SR))
    m = min(sig.shape[-1], buf.shape[-1] - s)
    if m > 0:
        buf[..., s:s + m] += sig[..., :m] * gain


def add_loop(buf, sig, start, gain=1.0, pan=0.0):
    """Mischt sig (mono/stereo) ab Sample 'start' in buf (2, n) – mit Umbruch am Ende (für nahtlose Loops)."""
    n = buf.shape[1]
    if sig.ndim == 1:
        th = (pan + 1.0) * np.pi / 4.0
        sig = np.stack([sig * math.cos(th), sig * math.sin(th)])
    sig = sig * gain
    start %= n
    pos = 0
    total = sig.shape[1]
    while pos < total:
        take = min(total - pos, n - start)
        buf[:, start:start + take] += sig[:, pos:pos + take]
        pos += take
        start = 0


# ------------------------------------------------------------- Hall
def make_ir(rt60=2.6, seed=1, damp=1.0, pre=0.015):
    """Synthetischer Hall (Stereo): tiefe Anteile klingen länger nach als hohe -> warm."""
    n = int(rt60 * 1.25 * SR)
    t = np.arange(n) / SR
    k = rt60 / 6.91
    ir = np.zeros((2, n))
    for ch in range(2):
        nz = np.random.default_rng(seed * 10 + ch).standard_normal(n)
        lo = lowpass(nz, 500, 1)
        mid = bandpass(nz, 500, 3200, 1)
        hi = highpass(nz, 3200, 1)
        ir[ch] = (lo * np.exp(-t / (k * 1.2)) + mid * np.exp(-t / k) * 0.8
                  + hi * np.exp(-t / (k * 0.4)) * 0.25 * damp)
        ir[ch] *= np.minimum(1.0, t / 0.04)
    ir = np.concatenate([np.zeros((2, int(pre * SR))), ir], axis=1)
    return ir / np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))


def reverb_circular(x, ir):
    """Hall, der am Ende der Loop-Länge wieder vorn einsetzt (nahtlos). x: (2, n)."""
    n = x.shape[1]
    out = np.zeros_like(x)
    for ch in range(2):
        out[ch] = np.fft.irfft(np.fft.rfft(x[ch]) * np.fft.rfft(ir[ch], n), n)
    return out


def reverb_once(x, ir, wet):
    """Hall für Einzelklänge. x: (n,) oder (2, n). Gibt Stereo mit Nachhall-Schwanz zurück."""
    if x.ndim == 1:
        x = np.stack([x, x])
    n = x.shape[1] + ir.shape[1]
    big = 1 << int(np.ceil(np.log2(n)))
    out = np.zeros((2, n))
    out[:, :x.shape[1]] = x
    for ch in range(2):
        y = np.fft.irfft(np.fft.rfft(x[ch], big) * np.fft.rfft(ir[ch], big), big)[:n]
        out[ch] += wet * y
    return out


def trim_tail(x, thresh_db=-48.0, fade=0.25):
    peak = np.max(np.abs(x))
    mag = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    idx = np.where(mag > peak * db(thresh_db))[0]
    end = int(idx[-1]) + 1 if len(idx) else x.shape[-1]
    return fade_edges(x[..., :end], 0.001, min(fade, end / SR / 2))


# ===================================================================== Instrumente (alle mono)
def pluck(f, dur, vel=1.0, bright=0.86, seed=0):
    """Gezupfte Saite (Harfe / Nylongitarre): hohe Obertöne klingen schneller aus."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    tau1 = 2.6 * (261.6 / f) ** 0.35
    kmax = int(min(18, SR * 0.42 / f))
    r = np.random.default_rng(seed)
    out = np.zeros(n)
    for k in range(1, kmax + 1):
        fk = f * k * math.sqrt(1.0 + 0.00035 * k * k)
        amp = (bright ** (k - 1)) / (k ** 1.1)
        tau = tau1 / (1.0 + 0.75 * (k - 1) ** 1.05)
        out += amp * np.exp(-t / tau) * np.sin(2 * np.pi * fk * t + r.uniform(0, 0.5))
    na = max(1, int(0.002 * SR))
    out[:na] *= np.linspace(0.0, 1.0, na)
    out *= 0.5 + 0.5 * np.cos(np.pi * np.clip((t - (dur - 0.05)) / 0.05, 0, 1))
    return out * vel


def bell(f, dur, vel=1.0, seed=0):
    """Weiches Glöckchen / Celesta / Spieluhr."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    scale = (523.0 / f) ** 0.25
    parts = ((1.0, 1.0, 2.8), (2.0, 0.26, 1.6), (3.0, 0.09, 0.9), (4.15, 0.15, 0.7), (5.4, 0.04, 0.4))
    out = np.zeros(n)
    for ratio, amp, tau in parts:
        if f * ratio > SR * 0.42:
            continue
        out += amp * np.exp(-t / (tau * scale)) * np.sin(2 * np.pi * f * ratio * t + r.uniform(0, 0.6))
    na = max(1, int(0.002 * SR))
    out[:na] *= np.linspace(0.0, 1.0, na)
    out *= 0.5 + 0.5 * np.cos(np.pi * np.clip((t - (dur - 0.08)) / 0.08, 0, 1))
    return out * vel


def ep(f, dur, vel=0.8):
    """Weiches E-Piano (FM): am Anfang etwas heller, dann schnell rund und warm."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = (0.8 + 1.3 * vel) * np.exp(-t / 0.45) + 0.16
    car = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = 0.10 * vel * np.exp(-t / 0.08) * np.sin(2 * np.pi * f * 7.0 * t)
    body = 0.30 * np.exp(-t / 0.6) * np.sin(2 * np.pi * f * 2.0 * t)
    return (car + tine + body) * note_env(n, a=0.008, tau=max(0.9, dur * 0.7), r=min(0.3, dur * 0.3)) * vel


def pad(notes, dur, attack=1.1, release=1.7, seed=0):
    """Warmer Klangteppich (Stereo): leicht verstimmte, dreieckähnliche Schwingungen."""
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    left = np.zeros(n)
    right = np.zeros(n)
    for m in notes:
        f = midi(m)
        for det, wl, wr in ((-8, 1.0, 0.25), (0, 0.75, 0.75), (7, 0.25, 1.0)):
            fd = f * 2.0 ** (det / 1200.0)
            lfo = 1.0 + 0.10 * np.sin(2 * np.pi * r.uniform(0.12, 0.3) * t + r.uniform(0, 6.28))
            osc = np.zeros(n)
            for k in range(1, 7):
                if fd * k > SR * 0.4:
                    break
                amp = (1.0 / k ** 2) if k % 2 else (0.35 / k ** 2)
                osc += amp * np.sin(2 * np.pi * fd * k * t + r.uniform(0, 6.28))
            osc *= lfo
            left += osc * wl
            right += osc * wr
    env = np.ones(n)
    na = min(int(attack * SR), n // 2)
    nr = min(int(release * SR), n // 2)
    env[:na] = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    env[-nr:] = np.minimum(env[-nr:], 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr))
    return np.stack([left * env, right * env])


def bass(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = (np.sin(2 * np.pi * f * t)
           + 0.32 * np.exp(-t / 0.9) * np.sin(2 * np.pi * f * 2 * t)
           + 0.12 * np.exp(-t / 0.5) * np.sin(2 * np.pi * f * 3 * t))
    return out * note_env(n, a=0.015, tau=1.5, r=0.25) * vel


def marimba(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = (np.exp(-t / 0.22) * np.sin(2 * np.pi * f * t)
           + 0.35 * np.exp(-t / 0.06) * np.sin(2 * np.pi * f * 4 * t)
           + 0.12 * np.exp(-t / 0.025) * np.sin(2 * np.pi * f * 10 * t))
    na = max(1, int(0.001 * SR))
    out[:na] *= np.linspace(0.0, 1.0, na)
    out *= 0.5 + 0.5 * np.cos(np.pi * np.clip((t - (dur - 0.05)) / 0.05, 0, 1))
    return out * vel


def thump(vel=1.0):
    """Weicher, tiefer Herzschlag-Puls."""
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    f = 46.0 + 70.0 * np.exp(-t / 0.035)
    out = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.1)
    return fade_edges(out, 0.004, 0.05) * vel


# ===================================================================== Komposition
BPM = 66.0
BEAT = 60.0 / BPM
BARS = 32                                   # 2 x 16 Takte
LOOP_N = int(round(BARS * 4 * BEAT * SR))

# Akkorde: Bass-Grundton (MIDI), Stimmen von tief nach hoch (MIDI), Tonvorrat (Tonhöhenklassen)
CH = {
    "Fmaj9": dict(root=41, notes=[53, 60, 64, 67, 69], pcs={5, 9, 0, 4, 7}),
    "Am9": dict(root=45, notes=[57, 64, 67, 71, 72], pcs={9, 0, 4, 7, 11}),
    "Bbmaj9": dict(root=46, notes=[58, 65, 69, 72, 74], pcs={10, 2, 5, 9, 0}),
    "Cadd9": dict(root=48, notes=[55, 60, 64, 69, 74], pcs={0, 4, 7, 9, 2}),
    "Dm9": dict(root=50, notes=[57, 62, 65, 72, 76], pcs={2, 5, 9, 0, 4}),
    "Gm9": dict(root=43, notes=[55, 58, 62, 65, 69], pcs={7, 10, 2, 5, 9}),
    "C9sus": dict(root=48, notes=[55, 58, 62, 65, 72], pcs={0, 2, 5, 7, 10}),
    "Csus4": dict(root=48, notes=[55, 60, 65, 67, 72], pcs={0, 5, 7, 2}),
    "Gm7": dict(root=43, notes=[55, 58, 62, 65, 67], pcs={7, 10, 2, 5}),
    "C13sus": dict(root=48, notes=[58, 62, 65, 69, 72], pcs={0, 5, 7, 10, 2, 9}),
}

# 16 Takte; je Takt: (Startschlag, Akkord). Danach wiederholt sich alles (die zweite Runde bekommt Melodie).
PROG = [
    [(0, "Fmaj9")], [(0, "Am9")], [(0, "Bbmaj9")], [(0, "Cadd9")],
    [(0, "Fmaj9")], [(0, "Dm9")], [(0, "Bbmaj9")], [(0, "Csus4"), (2, "Cadd9")],
    [(0, "Dm9")], [(0, "Gm9")], [(0, "Bbmaj9")], [(0, "C9sus")],
    [(0, "Dm9")], [(0, "Bbmaj9")], [(0, "Gm7"), (2, "C13sus")], [(0, "Fmaj9")],
]

# Melodie (zweite Runde): (MIDI-Note, Schlag, Länge in Schlägen). Nur Töne, die zum Akkord passen.
MELODY = [
    [(81, 0, 2), (79, 2, 1), (81, 3, 1)],
    [(84, 0, 1.5), (81, 1.5, .5), (79, 2, 2)],
    [(77, 0, 1), (81, 1, 1), (84, 2, 2)],
    [(86, 0, 1.5), (84, 1.5, .5), (81, 2, 2)],
    [(81, 0, 2), (79, 2, 1), (77, 3, 1)],
    [(81, 0, 1), (77, 1, 1), (74, 2, 2)],
    [(77, 0, 2), (81, 2, 1), (84, 3, 1)],
    [(79, 0, 2), (81, 2, 1), (79, 3, 1)],
    [(86, 0, 2), (84, 2, 1), (81, 3, 1)],
    [(79, 0, 1.5), (81, 1.5, .5), (86, 2, 2)],
    [(84, 0, 1), (81, 1, 1), (77, 2, 2)],
    [(79, 0, 1), (77, 1, 1), (74, 2, 2)],
    [(77, 0, 1.5), (81, 1.5, .5), (86, 2, 2)],
    [(84, 0, 2), (81, 2, 2)],
    [(86, 0, 2), (84, 2, 2)],
    [(81, 0, 4)],
]

ARP_PATTERNS = [[0, 2, 3, 4, 3, 2, 3, 1], [0, 3, 2, 4, 2, 3, 1, 2]]
SWING = 0.08                                 # jede zweite Achtel kommt minimal später


def chord_at(bar, beat):
    seg = PROG[bar % 16]
    cur = seg[0][1]
    for start, name in seg:
        if beat >= start - 1e-9:
            cur = name
    return cur


def segments(bar):
    seg = PROG[bar % 16]
    for i, (b0, name) in enumerate(seg):
        b1 = seg[i + 1][0] if i + 1 < len(seg) else 4
        yield b0, b1, name


def S(bar, beat):
    return int(round((bar * 4 + beat) * BEAT * SR))


def check_composition():
    """Sicherheitsnetz: jede Melodienote muss zum Akkord passen, sonst bricht das Skript ab."""
    for i, notes in enumerate(MELODY):
        for note, beat, _ in notes:
            ch = chord_at(i, beat)
            assert note % 12 in CH[ch]["pcs"], f"Takt {i + 1}: Note {note} passt nicht zu {ch}"


def new_buf():
    return np.zeros((2, LOOP_N), dtype=np.float32)


def render_bass():
    buf = new_buf()
    for bar in range(BARS):
        for b0, b1, name in segments(bar):
            f = midi(CH[name]["root"])
            if b1 - b0 >= 4:
                add_loop(buf, bass(f, 2.0 * BEAT + 0.2, 0.9), S(bar, b0))
                add_loop(buf, bass(f, 2.0 * BEAT + 0.2, 0.55), S(bar, b0 + 2))
            else:
                add_loop(buf, bass(f, (b1 - b0) * BEAT + 0.2, 0.9), S(bar, b0))
    return buf


def render_pad():
    buf = new_buf()
    for bar in range(BARS):
        for b0, b1, name in segments(bar):
            dur = (b1 - b0) * BEAT
            att = min(1.1, dur * 0.55)
            add_loop(buf, pad(CH[name]["notes"][:4], dur, attack=att, seed=bar * 7 + int(b0)), S(bar, b0))
    return buf


def render_arp():
    buf = new_buf()
    rng = np.random.default_rng(11)
    for bar in range(BARS):
        pat = ARP_PATTERNS[bar % 2]
        second = bar >= 16
        for e in range(8):
            beat = e * 0.5 + (SWING * 0.5 if e % 2 else 0.0)
            m = CH[chord_at(bar, e * 0.5)]["notes"][pat[e]]
            vel = (0.80 if e % 4 == 0 else 0.55) * rng.uniform(0.88, 1.08) * (1.05 if second else 1.0)
            note = pluck(midi(m), 2.5, vel, bright=0.90 if second else 0.84, seed=bar * 8 + e)
            add_loop(buf, note, S(bar, beat) + int(rng.normal(0, 0.004) * SR), 1.0, (pat[e] - 2) * 0.16)
    return buf


def render_ep():
    buf = new_buf()
    rng = np.random.default_rng(21)
    for bar in range(16, BARS):
        for b0, b1, name in segments(bar):
            vs = CH[name]["notes"][1:4]
            hits = [(b0, min(2.5, b1 - b0), 0.42)]
            if b1 - b0 >= 4:
                hits.append((b0 + 2.5, 1.5, 0.30))
            for hb, hl, hv in hits:
                for k, m in enumerate(vs):
                    nt = ep(midi(m), hl * BEAT + 0.9, hv * rng.uniform(0.9, 1.05))
                    add_loop(buf, nt, S(bar, hb) + int(rng.normal(0, 0.005) * SR), 1.0, -0.3 + 0.2 * k)
    return buf


def render_melody():
    buf = new_buf()
    for i, notes in enumerate(MELODY):
        bar = 16 + i
        for note, beat, length in notes:
            nt = bell(midi(note), length * BEAT + 2.2, 0.85, seed=i * 5 + int(beat * 2))
            add_loop(buf, nt, S(bar, beat), 1.0, 0.12)
    return buf


def render_sparkle():
    """Leises Schnee-Funkeln: zufällige hohe Glöckchen, immer passend zum Akkord."""
    buf = new_buf()
    rng = np.random.default_rng(5)
    pool = [89, 91, 93, 96, 98, 101]               # F6 G6 A6 C7 D7 F7
    for _ in range(46):
        tt = rng.uniform(0, BARS * 4 * BEAT)
        bar, beat = int(tt // (4 * BEAT)), (tt % (4 * BEAT)) / BEAT
        pcs = CH[chord_at(bar, beat)]["pcs"]
        opts = [m for m in pool if m % 12 in pcs]
        m = int(rng.choice(opts))
        add_loop(buf, bell(midi(m), 4.0, rng.uniform(0.35, 0.8), seed=int(tt * 10)),
                 int(tt * SR), 1.0, rng.uniform(-0.8, 0.8))
    return buf


def mix_stems(stems):
    """stems: Liste (Puffer, Lautstärke, Hallanteil, Hall). Alles nahtlos im Kreis gerechnet."""
    mix = np.zeros((2, LOOP_N))
    for buf, gain, wet, ir in stems:
        x = buf.astype(np.float64)
        mix += gain * (x + wet * reverb_circular(x, ir))
    return mix


def master(mix, rms_db, lp=6800.0):
    """Wärme (Höhen sanft abgesenkt), weiche Sättigung, dann auf einen ruhigen Hintergrund-Pegel (RMS)."""
    mix = highpass(mix, 38.0, 2)
    mix = lowpass(mix, lp, 2)
    mix = mix / np.max(np.abs(mix))
    mix = np.tanh(1.35 * mix) / np.tanh(1.35)
    mix = mix / np.sqrt(np.mean(mix ** 2)) * db(rms_db)
    peak = np.max(np.abs(mix))
    if peak > db(-3.0):
        mix = mix / peak * db(-3.0)
    return mix


def build_music():
    check_composition()
    hall = make_ir(3.4, seed=1)
    room = make_ir(1.5, seed=2)
    print("  Musik: rendere Stimmen ...")
    stems = [
        (render_bass(), 1.05, 0.10, room),
        (render_pad(), 0.30, 0.35, hall),
        (render_arp(), 0.55, 0.45, hall),
        (render_ep(), 0.40, 0.50, hall),
        (render_melody(), 0.78, 0.65, hall),
        (render_sparkle(), 0.28, 0.90, hall),
    ]
    mix = master(mix_stems(stems), -20.0)
    save_ogg("music_calm", mix)


def build_alert_layer():
    """Zweite Ebene für Gefahr: leise Marimba-Sechzehntel und weicher Puls – gleiche Akkorde, gleiche Länge."""
    rng = np.random.default_rng(31)
    marim = new_buf()
    pulse = new_buf()
    pat = [0, 2, 4, 2, 1, 3, 4, 3, 0, 2, 3, 2, 1, 3, 4, 3]
    for bar in range(BARS):
        for s in range(16):
            beat = s * 0.25
            m = CH[chord_at(bar, beat)]["notes"][pat[s]] + 12
            vel = (0.62 if s % 4 == 0 else 0.34) * rng.uniform(0.9, 1.08)
            add_loop(marim, marimba(midi(m), 0.5, vel), S(bar, beat) + int(rng.normal(0, 0.003) * SR),
                     1.0, 0.3 if s % 2 else -0.3)
        add_loop(pulse, thump(0.8), S(bar, 0.0))
        add_loop(pulse, thump(0.6), S(bar, 2.0))
        add_loop(pulse, thump(0.22), S(bar, 3.5))
    mix = mix_stems([(marim, 0.55, 0.35, make_ir(1.3, seed=4)), (pulse, 0.9, 0.05, make_ir(0.8, seed=5))])
    mix = master(mix, -25.0, lp=5200.0)
    save_ogg("music_alert", mix)


# ===================================================================== Ambiente (Loops)
def build_wind(seconds=32.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1.0 / SR)
    chans = []
    for ch in range(2):
        r = np.random.default_rng(500 + ch)

        def shaped(lo_corner, hi_corner, tilt):
            mag = np.zeros_like(f)
            ok = f > 30
            mag[ok] = (f[ok] / 150.0) ** (-tilt)
            mag *= 1.0 / np.sqrt(1 + (f / hi_corner) ** 4)
            mag *= 1.0 / np.sqrt(1 + (lo_corner / np.maximum(f, 1e-3)) ** 4)
            spec = mag * np.exp(1j * r.uniform(0, 2 * np.pi, len(f)))
            spec[0] = 0
            x = np.fft.irfft(spec, n)
            return x / np.std(x)

        soft = shaped(55, 380, 0.9)
        bright = shaped(120, 1300, 0.7)
        ph = r.uniform(0, 2 * np.pi, 5)
        gust = (0.52 + 0.22 * np.sin(2 * np.pi * 2 * t / seconds + ph[0])
                + 0.16 * np.sin(2 * np.pi * 3 * t / seconds + ph[1])
                + 0.08 * np.sin(2 * np.pi * 7 * t / seconds + ph[2])
                + 0.04 * np.sin(2 * np.pi * 11 * t / seconds + ph[3]))
        gust = np.clip(gust, 0.05, 1.0)
        y = (soft + bright * gust ** 2 * 0.8) * (0.35 + 0.65 * gust)
        # ganz leises Heulen, nur in den stärksten Böen (Phase kehrt am Ende exakt zurück -> nahtlos)
        fw = 410 + 70 * np.sin(2 * np.pi * 3 * t / seconds + ph[4])
        cycles = np.sum(fw) / SR
        fw = fw * (round(cycles) / cycles)
        howl = np.sin(2 * np.pi * np.cumsum(fw) / SR) * np.clip((gust - 0.7) / 0.3, 0, 1) ** 2
        y = y + 0.12 * howl * np.std(y)
        chans.append(y)
    x = np.stack(chans)
    x = lowpass(x, 3000, 1)
    save_ogg("amb_wind", x / np.std(x) * 0.06, peak_db=None)


def add_wrap_1d(buf, sig, start, gain=1.0):
    """Wie add_loop, aber für einen einkanaligen Puffer (Umbruch am Ende)."""
    n = len(buf)
    start %= n
    pos = 0
    while pos < len(sig):
        take = min(len(sig) - pos, n - start)
        buf[start:start + take] += sig[pos:pos + take] * gain
        pos += take
        start = 0


def build_fire(seconds=16.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(900)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mag = np.zeros_like(f)
    ok = f > 20
    mag[ok] = 1.0 / np.maximum(f[ok], 1.0)
    mag *= 1.0 / np.sqrt(1 + (f / 420.0) ** 4)
    spec = mag * np.exp(1j * r.uniform(0, 2 * np.pi, len(f)))
    spec[0] = 0
    rumble = np.fft.irfft(spec, n)
    rumble /= np.std(rumble)
    flick = (0.75 + 0.25 * np.sin(2 * np.pi * 5 * t / seconds + 1.0)
             + 0.10 * np.sin(2 * np.pi * 13 * t / seconds + 2.0))
    hiss = bandpass(r.standard_normal(n), 2200, 7000, 1)
    hiss /= np.std(hiss)
    hiss_env = 0.5 + 0.5 * np.sin(2 * np.pi * 9 * t / seconds + 0.5) * np.sin(2 * np.pi * 4 * t / seconds)
    buf = rumble * flick * 0.6 + hiss * hiss_env * 0.03
    # Knistern: viele winzige Knackser, ab und zu ein lauterer Knall - am Ende geht es vorn weiter
    for _ in range(int(seconds * 14)):
        pos = int(r.integers(0, n))
        ln = int(r.uniform(0.004, 0.03) * SR)
        tt = np.arange(ln) / SR
        burst = r.standard_normal(ln) * np.exp(-tt / r.uniform(0.003, 0.012))
        c = r.uniform(1200, 4600)
        add_wrap_1d(buf, bandpass(burst, c * 0.6, c * 1.5, 1), pos, float(r.lognormal(-0.5, 0.6)) * 0.62)
    for _ in range(int(seconds * 0.45)):
        pos = int(r.integers(0, n))
        ln = int(0.05 * SR)
        tt = np.arange(ln) / SR
        body = np.sin(2 * np.pi * r.uniform(160, 380) * tt) * np.exp(-tt / 0.018)
        crack = bandpass(r.standard_normal(ln), 1000, 4200, 1) * np.exp(-tt / 0.006)
        add_wrap_1d(buf, body * 0.8 + crack * 0.8, pos, float(r.uniform(0.7, 1.2)) * 0.7)
    x = lowpass(highpass(buf, 60, 2), 6500, 1)
    x = x / np.std(x) * 0.07
    x = x / max(1.0, np.max(np.abs(x)) / 0.9)          # nie übersteuern
    save_ogg("amb_fire", x[None, :], peak_db=None)


# ===================================================================== Effekte
IR_SMALL = make_ir(0.9, seed=7)
IR_MED = make_ir(1.8, seed=8)
IR_HALL = make_ir(2.8, seed=9)


def mono(x):
    return (x[0] + x[1]) * 0.5


def noise(dur, seed=0):
    return np.random.default_rng(seed).standard_normal(int(dur * SR))


def sfx_step(seed):
    n = int(0.17 * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    thud = np.sin(2 * np.pi * np.cumsum(105 - 45 * np.minimum(1.0, t / 0.05)) / SR) * np.exp(-t / 0.032)
    grains = np.zeros(n)
    for _ in range(int(r.integers(9, 15))):
        t0 = r.uniform(0.0, 0.09)
        gl = int(r.uniform(0.003, 0.009) * SR)
        g = r.standard_normal(gl) * np.hanning(gl) * r.uniform(0.2, 0.7) * math.exp(-t0 / 0.07)
        s = int(t0 * SR)
        grains[s:s + gl] += g
    grains = bandpass(grains, 1300, 5200, 1)
    return fade_edges(lowpass(thud * 0.6 + grains * 1.15, 4800, 2), 0.002, 0.04)


def sfx_swing(seed, rising=True):
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    nz = np.random.default_rng(seed).standard_normal(n)
    centers = np.geomspace(450, 2600, 9)
    if not rising:
        centers = centers[::-1]
    out = np.zeros(n)
    for i, c in enumerate(centers):
        env = np.exp(-0.5 * ((t - (0.05 + 0.20 * i / 8)) / 0.05) ** 2)
        out += bandpass(nz, c * 0.7, c * 1.35, 1) * env
    return fade_edges(lowpass(out, 4000), 0.01, 0.08)


def sfx_hit(seed):
    r = np.random.default_rng(seed)
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    f = 62 + r.uniform(170, 215) * np.exp(-t / 0.045)
    thump_ = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.075)
    fr = float(r.choice([1568.0, 1760.0, 1976.0, 2093.0]))
    ping = (np.sin(2 * np.pi * fr * t) + 0.35 * np.sin(2 * np.pi * fr * 2.76 * t)) * np.exp(-t / 0.12) * 0.28
    click = bandpass(r.standard_normal(n), 1100, 3400, 1) * np.exp(-t / 0.012) * 0.55
    return fade_edges(lowpass(thump_ * 0.95 + ping + click, 7500), 0.001, 0.05)


def sfx_enemy_die():
    buf = np.zeros(int(1.3 * SR))
    tt = np.arange(int(0.25 * SR)) / SR
    bloop = np.sin(2 * np.pi * np.cumsum(190 + 380 * np.exp(-tt / 0.07)) / SR) * np.exp(-tt / 0.09) * 0.7
    place(buf, bloop, 0.0)
    for i, m in enumerate((93, 88, 84)):
        place(buf, bell(midi(m), 0.9, 0.5, seed=i), 0.06 + 0.1 * i, 0.5)
    place(buf, bandpass(noise(0.25, 3), 500, 2600) * np.exp(-tt / 0.08) * 0.35, 0.0)
    return mono(trim_tail(reverb_once(buf, IR_SMALL, 0.35)))


def sfx_hurt():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    bump = np.sin(2 * np.pi * np.cumsum(60 + 110 * np.exp(-t / 0.05)) / SR) * np.exp(-t / 0.07)
    f = 300 - 120 * (1 - np.exp(-t / 0.12))
    ph = 2 * np.pi * np.cumsum(f) / SR
    ooh = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * np.exp(-t / 0.12) * (1 - np.exp(-t / 0.01))
    thud = lowpass(noise(0.45, 4), 450) * np.exp(-t / 0.05) * 0.5
    return fade_edges(lowpass(bump * 0.9 + lowpass(ooh, 1000) * 0.35 + thud, 3000), 0.002, 0.08)


def sfx_alert():
    buf = np.zeros(int(0.5 * SR))
    place(buf, marimba(midi(76), 0.35, 0.9), 0.0)
    place(buf, marimba(midi(81), 0.35, 1.0), 0.085)
    return fade_edges(lowpass(buf, 6000), 0.001, 0.06)


def sfx_lunge():
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    f = 230 + 330 * np.clip(t / 0.16, 0, 1) ** 1.5
    env = np.sin(np.pi * np.clip(t / 0.2, 0, 1)) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env * 0.5
    air = lowpass(highpass(noise(0.28, 5), 1500), 4500) * env * 0.25
    return fade_edges(tone + air, 0.005, 0.06)


def sfx_levelup():
    buf = np.zeros((2, int(3.0 * SR)))
    length = int(1.8 * SR)
    for i, m in enumerate((77, 81, 84, 89)):                       # F5 A6 C6 F6 aufwärts
        top = bell(midi(m), 1.8, 0.55, seed=i)
        low = np.pad(ep(midi(m - 12), 1.2, 0.35), (0, length - int(1.2 * SR)))
        place(buf, np.stack([top + 0.5 * low] * 2), 0.1 * i)
    for i, m in enumerate((93, 96)):                               # Funkeln obendrauf
        nt = bell(midi(m), 1.4, 0.3, seed=20 + i)
        place(buf, np.stack([nt, nt * 0.6]) if i else np.stack([nt * 0.6, nt]), 0.5 + 0.17 * i)
    place(buf, pad([53, 60, 65, 69], 1.0, attack=0.35, release=1.4, seed=3), 0.0, 0.33)
    return trim_tail(reverb_once(buf, IR_HALL, 0.45))


def sfx_unlock():
    buf = np.zeros(int(1.6 * SR))
    place(buf, bell(midi(81), 1.2, 0.6, seed=1), 0.0)
    place(buf, bell(midi(88), 1.2, 0.5, seed=2), 0.11)
    place(buf, bell(midi(93), 0.9, 0.22, seed=3), 0.2)
    tt = np.arange(int(0.3 * SR)) / SR
    place(buf, np.sin(2 * np.pi * 98 * tt) * np.exp(-tt / 0.1) * 0.5, 0.0)
    return trim_tail(reverb_once(buf, IR_MED, 0.3))


def sfx_hover():
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    return fade_edges(lowpass(np.sin(2 * np.pi * 1500 * t) * np.exp(-t / 0.012) * 0.35
                              + np.sin(2 * np.pi * 3000 * t) * np.exp(-t / 0.006) * 0.1, 6000), 0.001, 0.02)


def sfx_click():
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    f = 520 + 260 * np.exp(-t / 0.03)
    return fade_edges(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05) * 0.6
                      + np.sin(2 * np.pi * 1560 * t) * np.exp(-t / 0.012) * 0.12, 0.001, 0.04)


def sweep(dur, f0, f1, seed, amp=0.25):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = noise(dur, seed)
    out = np.zeros(n)
    for i, c in enumerate(np.geomspace(f0, f1, 8)):
        env = np.exp(-0.5 * ((t - dur * (0.15 + 0.6 * i / 7)) / (dur * 0.17)) ** 2)
        out += bandpass(nz, c * 0.7, c * 1.4, 1) * env
    return fade_edges(lowpass(out, 3500), 0.02, 0.1) * amp


def sfx_open():
    buf = np.zeros(int(0.7 * SR))
    place(buf, sweep(0.5, 350, 1600, 11), 0.0)
    place(buf, bell(midi(84), 0.6, 0.5, seed=4), 0.06)
    return trim_tail(reverb_once(buf, IR_SMALL, 0.3))


def sfx_close():
    buf = np.zeros(int(0.6 * SR))
    place(buf, sweep(0.4, 1500, 350, 12), 0.0)
    place(buf, bell(midi(79), 0.5, 0.45, seed=5), 0.04)
    return trim_tail(reverb_once(buf, IR_SMALL, 0.3))


def sfx_deny():
    buf = np.zeros(int(0.3 * SR))
    for i, f0 in enumerate((250, 205)):
        n = int(0.14 * SR)
        t = np.arange(n) / SR
        place(buf, np.sin(2 * np.pi * np.cumsum(f0 - 55 * t / 0.14) / SR) * np.exp(-t / 0.035), 0.085 * i)
    return fade_edges(lowpass(buf, 1200), 0.002, 0.05)


def sfx_heal():
    buf = np.zeros(int(1.0 * SR))
    place(buf, bell(midi(84), 0.7, 0.5, seed=6), 0.0)
    place(buf, bell(midi(88), 0.7, 0.5, seed=7), 0.075)
    return trim_tail(reverb_once(buf, IR_MED, 0.3))


def sfx_death():
    buf = np.zeros((2, int(5.0 * SR)))
    for i, m in enumerate((76, 72, 69, 65, 62)):
        nt = ep(midi(m), 2.4, 0.5)
        place(buf, np.stack([nt, nt]), 0.45 * i, 0.4)
    place(buf, pad([50, 57, 62, 65], 2.4, attack=1.2, release=1.6, seed=9), 0.6, 0.30)
    return trim_tail(reverb_once(buf, IR_HALL, 0.5), fade=0.5)


def sfx_respawn():
    buf = np.zeros((2, int(4.0 * SR)))
    place(buf, pad([41, 53, 57, 60, 67], 1.8, attack=0.8, release=1.6, seed=10), 0.0, 0.40)
    for i, m in enumerate((65, 69, 72, 77, 81)):
        nt = pluck(midi(m), 2.0, 0.6, seed=i)
        place(buf, np.stack([nt, nt]), 0.35 + 0.13 * i, 0.5)
    nt = bell(midi(96), 1.8, 0.3, seed=30)
    place(buf, np.stack([nt, nt * 0.7]), 1.1)
    return trim_tail(reverb_once(buf, IR_HALL, 0.45), fade=0.4)


# ===================================================================== Ausgabe
def _norm(x, peak_db):
    p = np.max(np.abs(x))
    return x / p * db(peak_db) if p > 0 else x


def save_wav(name, x, peak_db):
    x = _norm(np.asarray(x, dtype=np.float64), peak_db)
    data = x.T if x.ndim == 2 else x[:, None]
    pcm = np.round(np.clip(data, -1.0, 1.0) * 32767).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name}.wav  {x.shape[-1] / SR:5.2f}s  {'stereo' if x.ndim == 2 else 'mono  '}  Spitze {peak_db:5.1f} dB")


def save_ogg(name, x, peak_db=None):
    x = np.asarray(x, dtype=np.float64)
    if peak_db is not None:
        x = _norm(x, peak_db)
    x = np.clip(x, -1.0, 1.0)
    path = os.path.join(OUT, name + ".ogg")
    data = x.T.astype(np.float32)
    try:
        import soundfile as sf
        # blockweise schreiben - große Puffer auf einmal können den Vorbis-Encoder zum Absturz bringen
        with sf.SoundFile(path, "w", samplerate=SR, channels=data.shape[1], format="OGG", subtype="VORBIS") as snd:
            for i in range(0, len(data), 1 << 14):
                snd.write(data[i:i + (1 << 14)])
    except ImportError:
        ff = shutil.which("ffmpeg")
        if ff is None:
            raise SystemExit("Für .ogg wird 'pip install soundfile' oder ffmpeg benötigt.")
        with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as tmp:
            tmp.write(data.tobytes())
        subprocess.run([ff, "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(data.shape[1]),
                        "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
        os.unlink(tmp.name)
    print(f"  {name}.ogg  {x.shape[-1] / SR:6.1f}s  {os.path.getsize(path) / 1024:6.0f} KB")


def build_sfx():
    for i, s in enumerate((101, 102, 103)):
        save_wav(f"sfx_step_{'abc'[i]}", sfx_step(s), -13.0)
    save_wav("sfx_swing_a", sfx_swing(201, True), -9.0)
    save_wav("sfx_swing_b", sfx_swing(202, False), -9.0)
    for i, s in enumerate((301, 302, 303)):
        save_wav(f"sfx_hit_{'abc'[i]}", sfx_hit(s), -4.0)
    save_wav("sfx_enemy_die", sfx_enemy_die(), -5.0)
    save_wav("sfx_hurt", sfx_hurt(), -5.0)
    save_wav("sfx_alert", sfx_alert(), -8.0)
    save_wav("sfx_lunge", sfx_lunge(), -10.0)
    save_wav("sfx_levelup", sfx_levelup(), -5.0)
    save_wav("sfx_unlock", sfx_unlock(), -6.0)
    save_wav("sfx_ui_hover", sfx_hover(), -20.0)
    save_wav("sfx_ui_click", sfx_click(), -12.0)
    save_wav("sfx_ui_open", sfx_open(), -12.0)
    save_wav("sfx_ui_close", sfx_close(), -12.0)
    save_wav("sfx_deny", sfx_deny(), -12.0)
    save_wav("sfx_heal", sfx_heal(), -12.0)
    save_wav("sfx_death", sfx_death(), -5.0)
    save_wav("sfx_respawn", sfx_respawn(), -5.0)


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "music"):
        print("Musik:")
        build_music()
        build_alert_layer()
    if what in ("all", "ambience"):
        print("Ambiente:")
        build_wind()
        build_fire()
    if what in ("all", "sfx"):
        print("Effekte:")
        build_sfx()
    print("Fertig ->", OUT)
