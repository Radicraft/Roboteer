#!/usr/bin/env python3
"""Generate every Roboteer fight sound into Arena/audio/.

These are SYNTHESISED sounds, but they are not blips: everything in here is built
the way the real object makes noise. Metal is a bank of second order modal
resonators struck by a short excitation, the bandsaw is a driven waveguide
(Karplus-Strong with a continuous friction excitation), impacts are a transient
plus a resonant body plus a low thump, and the arena ambience is band limited
noise circularly convolved with a decaying noise tail, which is a real (if small)
reverb and is exactly periodic so the 8 second loop has no seam at all.

Recorded or sampled replacements slot in by file name; see docs/audio-notes.md.

Output: 44.1 kHz, 16-bit WAV. Mono except `crowd_ambience_loop.wav`, which is
stereo. Every file is normalised to -3 dBFS peak. One shots get short fades so
nothing clicks; loops are NEVER faded (a fade puts a dip at the seam) and are
instead built to be seamless, then measured: the wrap-around sample step must be
no larger than the largest step inside the file or the build fails.

    python3 scripts/gen-sounds.py
    ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
    python3 scripts/gen-sounds.py --patch-imports     # loop flags + PCM on the loops
"""

import os
import re
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
PEAK_DBFS = -3.0
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "Arena", "audio")

# One seeded generator so re-running the script reproduces byte identical files.
RNG = np.random.default_rng(20260913)

# Files whose .import must say "loop forward" and "PCM, not QOA". A lossy codec
# smears the seam, which is audible as a tick once per loop.
LOOPS = [
    "motor_loop.wav",
    "spin_up_loop.wav",
    "saw_cut_loop.wav",
    "flame_loop.wav",
    "grinder_loop.wav",
    "disc_spin_loop.wav",
    "crowd_ambience_loop.wav",
]

_REPORT = []


# ---------------------------------------------------------------- primitives


def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def noise(n):
    return RNG.uniform(-1.0, 1.0, int(n))


def decay(t, tau):
    """Exponential amplitude decay, 1.0 at t = 0."""
    return np.exp(-t / tau)


def bandpass(x, lo, hi, order=2):
    lo = max(lo, 20.0)
    hi = min(hi, SR * 0.49)
    sos = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
    return sosfilt(sos, x)


def highpass(x, f, order=2):
    sos = butter(order, f / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, x)


def lowpass(x, f, order=2):
    sos = butter(order, min(f, SR * 0.49) / (SR / 2), btype="low", output="sos")
    return sosfilt(sos, x)


def saturate(x, drive=1.0):
    """Soft clip. Adds the odd harmonics a loaded motor or a hard hit really has.

    The mean is removed afterwards. tanh is an odd function, but a sum of harmonics
    with fixed phases is NOT amplitude-symmetric in time, so clipping it produces a
    real DC offset (measured -0.077 on the first motor_loop build, 11 % of full
    scale wasted and a thump on every play). Subtracting the mean is exact for a
    loop and costs nothing for a one shot.
    """
    y = np.tanh(drive * x) / np.tanh(drive)
    return y - np.mean(y)


# ---------------------------------------------------------------- modal metal


def modal(exc, freqs, amps, taus):
    """A bank of second order resonators driven by `exc`.

    This is the physical modelling core of every metal sound in the file. Each mode
    is the impulse response of a damped oscillator, realised as the two pole filter

        y[n] = 2 r cos(w) y[n-1] - r^2 y[n-2] + sin(w) x[n]

    with r = exp(-1 / (tau SR)). Because it is a FILTER and not a sum of sines, the
    excitation shapes the attack: a 0.4 ms noise click rings the whole bank at once
    (a struck plate), a long friction noise keeps it ringing (a saw in a cut), and a
    second strike 40 ms later adds to the modes still decaying from the first, which
    is what makes a clatter sound like one object rather than five.
    """
    exc = np.asarray(exc, dtype=np.float64)
    out = np.zeros(len(exc))
    for f, a, tau in zip(freqs, amps, taus):
        if f <= 0.0 or f >= SR * 0.49:
            continue
        w = 2.0 * np.pi * f / SR
        r = float(np.exp(-1.0 / max(tau * SR, 1.0)))
        b = [a * np.sin(w), 0.0, 0.0]
        a_c = [1.0, -2.0 * r * np.cos(w), r * r]
        out += lfilter(b, a_c, exc)
    return out


def modal_periodic(exc, freqs, amps, taus):
    """`modal` for a loop: rings up on a tiled copy so the tail wraps into the head."""
    n = len(exc)
    y = modal(np.tile(exc, 3), freqs, amps, taus)
    return y[n:2 * n]


def steel_modes(f0, count=7, spread=1.0, seed_ratios=None):
    """Inharmonic mode set for a struck steel plate or shell.

    A plate's modes are not a harmonic series; they climb faster than n and are
    irrational against each other, which is exactly why metal sounds like metal and
    a harmonic stack sounds like a bell toy. These ratios are the flat-plate family
    (roughly n^1.35 with a jitter) rather than integers.
    """
    ratios = seed_ratios if seed_ratios is not None else [
        1.0, 1.59, 2.14, 2.96, 3.67, 4.83, 6.11, 7.42, 9.05,
    ]
    out = []
    for i, r in enumerate(ratios[:count]):
        out.append(f0 * r * (1.0 + spread * RNG.uniform(-0.02, 0.02)))
    return out


def strike(n, ms=0.5, hi=9000.0, lo=400.0):
    """The excitation: a very short filtered noise click. This is the hammer."""
    k = max(int(SR * ms / 1000.0), 2)
    e = np.zeros(int(n))
    e[:k] = noise(k) * np.hanning(k * 2)[:k][::-1]
    return bandpass(e, lo, hi)


def hit(dur, f0, taus, amps=None, ratios=None, strike_ms=0.5, strike_hi=9000.0,
        thump_f=0.0, thump_tau=0.06, thump_gain=0.0):
    """One struck metal object: transient -> modal body -> optional low thump."""
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    freqs = steel_modes(f0, count=len(taus), seed_ratios=ratios)
    if amps is None:
        amps = [1.0 / (1.0 + 0.8 * i) for i in range(len(taus))]
    body = modal(strike(n, strike_ms, strike_hi), freqs, amps, taus)
    out = body
    if thump_gain > 0.0 and thump_f > 0.0:
        # The low end of a real impact is not a sine: it is the pitch of the panel
        # falling as it gives, so sweep it down by a third of an octave.
        f = thump_f * (0.62 + 0.38 * decay(t, thump_tau * 0.6))
        thump = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, thump_tau)
        out = out + thump_gain * thump
    return out


# ---------------------------------------------------------------- waveguide


def waveguide(exc, freq, loop_gain=0.995, brightness=0.5):
    """Karplus-Strong / digital waveguide: a delay line with a lowpass in the loop.

    Struck with a short burst it is a plucked string; driven with continuous noise
    it is friction on a resonant body, which is what a bandsaw blade in a cut is.
    `brightness` is the loop filter's one pole coefficient: 1.0 keeps the harmonics,
    0.0 is a dull thud after two periods.
    """
    exc = np.asarray(exc, dtype=np.float64)
    n = len(exc)
    L = max(int(round(SR / freq)), 2)
    buf = np.zeros(L)
    out = np.zeros(n)
    idx = 0
    prev = 0.0
    a = np.clip(brightness, 0.0, 0.999)
    for i in range(n):
        v = buf[idx]
        prev = a * v + (1.0 - a) * prev          # one pole lowpass in the loop
        y = exc[i] + loop_gain * prev
        buf[idx] = y
        idx = idx + 1
        if idx >= L:
            idx = 0
        out[i] = y
    return out


# ---------------------------------------------------------------- loop tools


def periodic_noise(n, lo, hi, tilt=0.0):
    """Noise that is exactly periodic over n samples, so it loops without a seam.

    `tilt` in dB/octave shapes it: 0 is white, -3 is pink, -6 is brown/rumble.
    """
    n = int(n)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    mag = np.zeros(len(freqs))
    band = (freqs >= lo) & (freqs <= hi)
    ref = max(lo, 20.0)
    with np.errstate(divide="ignore", invalid="ignore"):
        oct_above = np.log2(np.maximum(freqs, 1e-6) / ref)
    mag[band] = 10.0 ** (tilt * oct_above[band] / 20.0)
    spec = mag * np.exp(1j * RNG.uniform(0.0, 2.0 * np.pi, len(freqs)))
    spec[0] = 0.0
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def circular_reverb(x, decay_s=0.45, pre_ms=8.0, hf_damp=4200.0):
    """A small room, applied by CIRCULAR convolution so a loop stays seamless.

    The impulse response is a decaying noise tail (the standard cheap-but-honest
    late reverberation model). Convolving circularly means the tail that runs off
    the end of the buffer wraps into the start, which is precisely what a genuinely
    continuous recording would have had there.
    """
    n = len(x)
    ir = np.zeros(n)
    m = min(int(decay_s * 3.0 * SR), n)
    tt = np.arange(m) / SR
    ir[:m] = noise(m) * np.exp(-tt / decay_s)
    pre = int(pre_ms * SR / 1000.0)
    if pre > 0:
        ir[:pre] = 0.0
    ir = lowpass(ir, hf_damp)
    ir /= np.sqrt(np.sum(ir * ir)) + 1e-12
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir), n)


def circular_filter(x, fn):
    """Run a normal (causal) filter on a loop without leaving a start transient."""
    n = len(x)
    return fn(np.tile(x, 3))[n:2 * n]


def crossfade_loop(x, n, fade_ms=60.0):
    """Make a seamless n sample loop out of n + fade samples of continuous material.

    The tail is equal-power blended into the head, so sample 0 of the result is
    (almost exactly) the sample that naturally followed sample n-1 in the source.
    That is why the wrap step comes out the same size as an ordinary interior step,
    and why the assert at the bottom of this file passes for the modelled loops
    that cannot be made exactly periodic by construction.
    """
    n = int(n)
    f = int(SR * fade_ms / 1000.0)
    assert len(x) >= n + f, "crossfade_loop needs n + fade samples"
    out = np.array(x[:n], dtype=np.float64)
    ramp = np.linspace(0.0, 1.0, f)
    fade_in = np.sin(0.5 * np.pi * ramp)
    fade_out = np.cos(0.5 * np.pi * ramp)
    out[:f] = out[:f] * fade_in + x[n:n + f] * fade_out
    return out


def lfo(t, hz_list, depth_list, dur):
    """Sum of sines whose periods all divide `dur`, so the modulation loops too."""
    out = np.ones(len(t))
    for hz, depth in zip(hz_list, depth_list):
        k = max(round(hz * dur), 1)             # snap to a whole number of cycles
        out += depth * np.sin(2.0 * np.pi * (k / dur) * t + RNG.uniform(0, 2 * np.pi))
    return out


# ---------------------------------------------------------------- output


def fade(x, in_ms=2.0, out_ms=6.0):
    n_in = min(int(SR * in_ms / 1000.0), len(x) // 2)
    n_out = min(int(SR * out_ms / 1000.0), len(x) // 2)
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    if n_out > 0:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return x


def normalise(x, dbfs=PEAK_DBFS):
    peak = float(np.max(np.abs(x)))
    if peak < 1e-9:
        return x
    return x * (10.0 ** (dbfs / 20.0)) / peak


def seam_report(name, x):
    """Prove the loop seam. Must be run on the NORMALISED mono-summed signal."""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    inner = float(np.max(np.abs(np.diff(mono))))
    wrap = abs(float(mono[0] - mono[-1]))
    ok = wrap <= inner
    print("      seam step %.6f vs max inner step %.6f  (%s)"
          % (wrap, inner, "seamless" if ok else "CLICKS"))
    if not ok:
        raise SystemExit("%s is not seamless" % name)


def write(name, x, do_fade=True, in_ms=2.0, out_ms=6.0, loop=False):
    x = np.asarray(x, dtype=np.float64)
    if do_fade and not loop:
        x = fade(x, in_ms, out_ms)
    x = normalise(x)
    if loop:
        seam_report(name, x)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    wavfile.write(path, SR, pcm)
    chans = 1 if pcm.ndim == 1 else pcm.shape[1]
    frames = pcm.shape[0]
    print("%-26s %6d frames  %6.3f s  %s%s"
          % (name, frames, frames / SR, "stereo" if chans == 2 else "mono",
             "  LOOP" if loop else ""))
    _REPORT.append((name, frames / SR, chans, loop))
    return path


# ================================================================ the sounds
#
# Every function returns a float array at any scale; `write` normalises.


# ---------------------------------------------------------------- collect

def bolt_collect():
    """45 ms. A shorn steel nut hitting the hopper: a hard tick, then the nut's own
    modes ringing for a few milliseconds. The modes are high and tightly damped
    because the object is small; that, not the pitch, is what makes it read as a
    bolt rather than a bell. The collect ramp pitches this by a semitone per bolt
    (brief-v3 §6), so it has to stay clean two octaves up: nothing below 900 Hz.
    """
    n = int(0.045 * SR)
    t = np.arange(n) / SR
    exc = strike(n, ms=0.35, hi=13000.0, lo=1200.0)
    body = modal(
        exc,
        [1760.0, 2870.0, 3940.0, 5310.0, 7180.0, 9640.0],
        [1.0, 0.72, 0.55, 0.40, 0.26, 0.15],
        [0.0125, 0.0090, 0.0068, 0.0048, 0.0032, 0.0021],
    )
    # A trace of air so the tick has a leading edge above the modal band.
    air = 0.18 * highpass(noise(n), 6000.0) * decay(t, 0.0016)
    return body * decay(t, 0.016) + air


# ---------------------------------------------------------------- impacts

def impact_light(variant):
    """A scrape or a graze: a bright transient, a small panel resonance, no weight.

    Three variants exist purely so a fast exchange does not machine-gun one sample.
    They differ in the panel's fundamental, its damping and the transient's colour,
    which is the difference between hitting a corner, a flat and an edge.
    """
    specs = [
        # f0, taus, strike ms, strike hi, scrape band, scrape tau
        (486.0, [0.034, 0.026, 0.019, 0.013, 0.009], 0.45, 9000.0, (1500, 6200), 0.022),
        (612.0, [0.028, 0.021, 0.015, 0.011, 0.007], 0.30, 13000.0, (2200, 9000), 0.016),
        (398.0, [0.042, 0.031, 0.023, 0.016, 0.011], 0.60, 8500.0, (1100, 5600), 0.030),
    ]
    f0, taus, ms, shi, band, stau = specs[variant]
    dur = 0.130 + 0.012 * variant
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    # A graze has a low end, but only as a hint: on a phone speaker anything under
    # 200 Hz is nearly gone, so a light hit that spends half its energy there just
    # sounds quiet. See the phone-speaker balance note in docs/audio-notes.md.
    body = hit(dur, f0, taus, strike_ms=ms, strike_hi=shi,
               thump_f=152.0, thump_tau=0.020, thump_gain=0.16)
    scrape = 0.45 * bandpass(noise(n), band[0], band[1]) * decay(t, stau)
    return body * decay(t, 0.055) + scrape


def impact_heavy(variant):
    """A real hit: a spinner into a plate. Three layers, and the order matters.

    1. CRACK, the first 3 ms: broadband, the sound of two surfaces arriving.
    2. BODY: the victim plate's modes, long enough to hear the metal, saturated a
       little so the loud part of the hit has the harmonics a plate driven past
       linearity actually produces.
    3. THUMP: the low end, pitch falling, which is the mass rather than the metal.
    """
    specs = [
        (232.0, [0.185, 0.150, 0.118, 0.082, 0.058, 0.040], 128.0, 0.100, 0.52),
        (288.0, [0.150, 0.122, 0.094, 0.068, 0.046, 0.031], 146.0, 0.084, 0.46),
        (196.0, [0.230, 0.186, 0.142, 0.101, 0.070, 0.048], 108.0, 0.122, 0.60),
    ]
    f0, taus, thf, thtau, ring_len = specs[variant]
    dur = 0.44 + 0.06 * variant
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = hit(dur, f0, taus, strike_ms=0.9, strike_hi=7000.0)
    body = saturate(body * 1.6, 1.4)
    crack = 0.85 * bandpass(noise(n), 900.0, 9000.0) * decay(t, 0.0085)
    f = thf * (0.62 + 0.38 * decay(t, 0.045))
    thump = 0.85 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, thtau)
    thump += 0.40 * bandpass(noise(n), 90.0, 420.0) * decay(t, thtau * 0.5)
    return 0.9 * body * decay(t, ring_len) + crack + thump


# ---------------------------------------------------------------- weapons

def flipper_fire():
    """Solenoid valve click, 120 ms of gas, then the arm hitting its stop.

    The hiss is not flat noise: a real pneumatic escape has a nozzle formant, so
    the noise runs through a resonant band that opens as the port opens, and it
    stops DEAD when the ram reaches the end of its stroke rather than fading.
    """
    total = 0.400
    n = int(round(total * SR))
    t = np.arange(n) / SR
    x = np.zeros(n)

    # 1. the valve: a small, hard, very short solenoid click
    click = hit(0.035, 1420.0, [0.010, 0.007, 0.005, 0.0035], strike_ms=0.25,
                strike_hi=12000.0)
    x[:len(click)] += 0.55 * click

    # 2. the gas: nozzle formant on escaping air
    hiss_n = int(0.125 * SR)
    th = t[:hiss_n]
    swell = np.clip(th / 0.018, 0.0, 1.0) * (1.0 - np.clip((th - 0.085) / 0.030, 0.0, 1.0))
    raw = noise(hiss_n)
    port = (bandpass(raw, 2400.0, 5200.0) * 1.0
            + bandpass(raw, 700.0, 1800.0) * 0.45
            + highpass(raw, 7000.0) * 0.35)
    x[:hiss_n] += 0.9 * port * swell

    # 3. the stop: steel arm into a steel stop, with the rubber bump under it
    at = int(0.122 * SR)
    rest = total - 0.122
    thud = hit(rest, 168.0, [0.060, 0.048, 0.036, 0.025, 0.017], strike_ms=1.1,
               strike_hi=5200.0, thump_f=122.0, thump_tau=0.045, thump_gain=0.45)
    thud += 0.5 * lowpass(noise(len(thud)), 1400.0) * decay(t_axis(rest), 0.009)
    x[at:at + len(thud)] += 1.5 * thud
    return x


def axe_swing():
    """The arm moving before it lands: a whoosh, which is a noise band whose centre
    sweeps up and back down as the head passes the ear, plus the servo under it."""
    dur = 0.340
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    # Sweep by crossfading three bands rather than running a time varying filter.
    raw = noise(n)
    lo = bandpass(raw, 260.0, 900.0)
    mid = bandpass(raw, 900.0, 2600.0)
    hi = bandpass(raw, 2600.0, 7000.0)
    p = np.clip(t / dur, 0, 1)
    w_lo = np.clip(1.0 - 2.2 * p, 0, 1)
    w_hi = np.clip(2.2 * (p - 0.55), 0, 1)
    w_mid = np.clip(1.0 - w_lo - w_hi, 0, 1)
    air = (lo * w_lo + mid * w_mid + hi * w_hi) * env
    servo = 0.22 * saturate(np.sin(2.0 * np.pi * (210.0 + 340.0 * p) * t), 2.0) * env
    return air + servo


def axe_hit():
    """A hardened head into armour. Heavier and duller than impact_heavy: less ring,
    more thump, and a short wooden-ish knock from the shaft taking the shock."""
    dur = 0.520
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = hit(dur, 174.0, [0.140, 0.108, 0.080, 0.055, 0.038], strike_ms=1.3,
               strike_hi=6000.0)
    shaft = modal(strike(n, 0.8, 3500.0, 200.0),
                  [312.0, 705.0, 1190.0], [0.6, 0.35, 0.2], [0.028, 0.018, 0.012])
    f = 104.0 * (0.62 + 0.38 * decay(t, 0.040))
    thump = 0.58 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.110)
    crack = 0.7 * bandpass(noise(n), 700.0, 6500.0) * decay(t, 0.007)
    return saturate(1.3 * body + 0.7 * shaft, 1.2) * decay(t, 0.40) + thump + crack


def ram_hit():
    """A blunt ram: almost no bright content, a lot of mass, and the frame of the
    victim bot ringing a fifth below where a panel would."""
    dur = 0.460
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = hit(dur, 214.0, [0.105, 0.082, 0.060, 0.042, 0.028], strike_ms=1.8,
               strike_hi=4200.0)
    f = 96.0 * (0.62 + 0.38 * decay(t, 0.055))
    thump = 0.50 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.100)
    scuff = 0.60 * bandpass(noise(n), 300.0, 2600.0) * decay(t, 0.022)
    return saturate(1.6 * body, 1.1) * decay(t, 0.26) + thump + scuff


def crusher_clamp():
    """Hydraulic strain: the pump loading up, then the metal complaining.

    The creak is stick-slip, which is not a tone and not noise: it is a resonance
    excited by a burst train whose rate falls as the jaw slows against the load.
    That falling rate is the whole sound; a steady tremolo reads as a machine gun.
    """
    dur = 0.900
    n = int(round(dur * SR))
    t = np.arange(n) / SR

    # Pump: a low loaded hum that tightens as the pressure rises.
    rise = np.clip(t / 0.28, 0, 1)
    hum_f = 74.0 + 26.0 * rise
    hum = saturate(np.sin(2.0 * np.pi * np.cumsum(hum_f) / SR)
                   + 0.5 * np.sin(2.0 * np.pi * np.cumsum(hum_f * 2) / SR), 1.8)
    hum *= 0.32 * rise * (1.0 - np.clip((t - 0.62) / 0.24, 0, 1))

    # Stick-slip creak: burst train, rate 46 Hz falling to 9 Hz.
    rate = 46.0 * np.exp(-t / 0.34) + 9.0
    phase = np.cumsum(rate) / SR
    ticks = np.zeros(n)
    edges = np.where(np.diff(np.floor(phase)) > 0)[0]
    ticks[edges] = RNG.uniform(0.4, 1.0, len(edges))
    creak = modal(bandpass(ticks, 400.0, 5000.0),
                  [820.0, 1310.0, 2040.0, 3170.0],
                  [1.0, 0.62, 0.38, 0.2], [0.020, 0.014, 0.010, 0.007])
    creak *= np.clip((t - 0.10) / 0.12, 0, 1) * (1.0 - np.clip((t - 0.66) / 0.20, 0, 1))

    # Relief valve sighing off at the end, then the jaw seating.
    sigh = bandpass(noise(n), 1600.0, 6500.0) * np.clip((t - 0.60) / 0.06, 0, 1) \
        * decay(np.maximum(t - 0.60, 0), 0.10) * 0.4
    seat_at = int(0.70 * SR)
    seat = hit(dur - 0.70, 196.0, [0.055, 0.042, 0.030, 0.020], strike_ms=1.4,
               strike_hi=4200.0, thump_f=84.0, thump_tau=0.050, thump_gain=1.0)
    out = hum + 0.8 * creak + sigh
    out[seat_at:seat_at + len(seat)] += 1.1 * seat
    return out


# ---------------------------------------------------------------- parts off

def bounces(dur, offsets, gains, f0s, taus_by_hit, thump_f, thump_gain):
    """A falling object: several strikes into ONE buffer so the modes of hit 2 add
    to the modes of hit 1 still decaying. The gaps shorten geometrically because
    a real bounce does: each one is the restitution times the last."""
    n = int(round(dur * SR))
    out = np.zeros(n)
    for off, g, f0, taus in zip(offsets, gains, f0s, taus_by_hit):
        i = int(off * SR)
        rest = dur - off
        if rest <= 0.02:
            continue
        seg = hit(rest, f0, taus, strike_ms=0.7, strike_hi=8000.0,
                  thump_f=thump_f, thump_tau=0.030, thump_gain=thump_gain)
        out[i:i + len(seg)] += g * seg
    return out


def wheel_off():
    """A wheel shears off and rolls: rubber first (dull, low, no ring), then the hub
    finding the floor twice as it settles. Restitution 0.55 sets the gaps."""
    dur = 0.620
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    offs = [0.0, 0.195, 0.305, 0.372]
    x = bounces(dur, offs, [1.0, 0.44, 0.19, 0.09],
                [238.0, 262.0, 286.0, 305.0],
                [[0.030, 0.022, 0.015, 0.010]] * 4,
                thump_f=112.0, thump_gain=0.50)
    # Rubber: a lot of fast-decaying low noise, which is what kills the metal ring.
    rubber = np.zeros(n)
    for off, g in zip(offs, [1.0, 0.4, 0.17, 0.08]):
        i = int(off * SR)
        tb = t[:n - i]
        rubber[i:] += g * lowpass(noise(len(tb)), 850.0) * decay(tb, 0.016)
    # The tyre rolling away after it lands.
    roll = 0.20 * bandpass(noise(n), 90.0, 700.0) * np.clip((t - 0.22) / 0.10, 0, 1) \
        * decay(np.maximum(t - 0.22, 0), 0.22)
    return x + 1.10 * rubber + 1.4 * roll


def panel_off():
    """An armour panel tears off and clatters: a big flat plate, so long modes, a
    bright first arrival, and three diminishing slaps as it flips over."""
    dur = 0.720
    offs = [0.0, 0.148, 0.244, 0.300]
    x = bounces(
        dur, offs, [1.0, 0.55, 0.30, 0.16],
        [421.0, 468.0, 512.0, 556.0],
        [
            [0.090, 0.070, 0.052, 0.036, 0.024],
            [0.070, 0.054, 0.040, 0.028, 0.019],
            [0.052, 0.040, 0.030, 0.021, 0.014],
            [0.040, 0.031, 0.023, 0.016, 0.011],
        ],
        thump_f=104.0, thump_gain=0.8)
    n = len(x)
    t = np.arange(n) / SR
    tear = 0.5 * bandpass(noise(n), 1400.0, 9000.0) * decay(t, 0.014)
    return x + tear


# ---------------------------------------------------------------- loops

def motor_loop():
    """Seamless 1 s drive loop, two layers as the brief asks.

    LOW ELECTRIC HUM: a 55 Hz series, soft clipped, which is a brushed DC motor
    under load rather than a sine.
    GEARBOX WHINE: a tooth-mesh tone at 440 Hz with its own harmonics, amplitude
    modulated at the shaft rate so it has the slight once-per-revolution warble a
    real reduction box has.

    Every component's period divides one second (all frequencies are whole numbers
    of cycles per second, all modulators likewise, and the noise is synthesised in
    the frequency domain), so sample 0 continues from the last sample exactly and
    the file is NOT faded. `pitch_scale` at playback follows the throttle.
    """
    n = SR
    t = np.arange(n) / SR
    dur = 1.0

    hum = np.zeros(n)
    f0 = 55
    for h, amp in ((1, 1.0), (2, 0.62), (3, 0.30), (4, 0.20), (5, 0.11), (7, 0.07), (9, 0.04)):
        hum += amp * np.sin(2.0 * np.pi * (f0 * h) * t + RNG.uniform(0, 2 * np.pi))
    hum = saturate(hum * 0.8, 1.5) * 0.52

    whine = np.zeros(n)
    for f, amp in ((440, 0.26), (880, 0.125), (1320, 0.062), (1760, 0.028)):
        whine += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    whine *= lfo(t, [11.0], [0.35], dur)          # once per shaft revolution

    hash_ = 0.30 * periodic_noise(n, 300.0, 5200.0, tilt=-2.0)
    load = lfo(t, [3.0, 7.0], [0.06, 0.035], dur)
    return (hum + whine + hash_) * load


def spin_up_loop():
    """A spinner's weapon motor, as a LOOP that is pitched by readiness.

    It is written at the low end of its range (fundamental 180 Hz) with a strong
    harmonic stack and a broad air roar, because a sound that is pitched UP by up
    to an octave must not already be bright or it turns into a whistle. fx maps
    readiness 0..1 to pitch_scale 0.55..2.1, so the whole rev is one file and the
    loop never restarts.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h, amp in ((1, 0.55), (2, 1.0), (3, 0.62), (4, 0.40), (5, 0.26),
                   (6, 0.16), (8, 0.09), (10, 0.05)):
        x += amp * np.sin(2.0 * np.pi * (180 * h) * t + RNG.uniform(0, 2 * np.pi))
    x = saturate(x * 0.5, 1.2)
    # Air being thrown off the blade tips: noise gated by the blade passing rate.
    blade = 0.5 + 0.5 * np.sin(2.0 * np.pi * 360 * t)
    roar = 0.45 * periodic_noise(n, 220.0, 6800.0, tilt=-3.0) * (0.55 + 0.45 * blade)
    bearing = 0.10 * periodic_noise(n, 2400.0, 9000.0, tilt=-1.0)
    return (x + roar + bearing) * lfo(t, [5.0], [0.05], dur)


def saw_cut_loop():
    """A bandsaw in a cut. The whine is a DRIVEN WAVEGUIDE, not an oscillator.

    A blade in a cut is a resonant body under continuous friction excitation, so
    that is literally how it is built: band limited noise is fed into a Karplus-
    Strong delay line tuned to the blade's ring (a waveguide), whose loop filter
    sets how bright the ring stays. The result has the slightly unstable, breathy
    pitch a real blade has and that an oscillator never gets.

    On top of it: the grind, which is noise amplitude modulated at the tooth rate,
    and the motor underneath. Seamless by crossfade, because a waveguide's output
    is not exactly periodic over any convenient length.
    """
    dur = 1.20
    n = int(dur * SR)
    fade_n = int(0.08 * SR)
    m = n + fade_n

    t = np.arange(m) / SR
    friction = bandpass(noise(m), 700.0, 9000.0) * (0.6 + 0.4 * np.abs(noise(m)))
    blade = waveguide(friction * 0.35, 612.0, loop_gain=0.982, brightness=0.72)
    blade += 0.5 * waveguide(friction * 0.20, 1477.0, loop_gain=0.960, brightness=0.85)
    blade = saturate(blade * 0.35, 1.3) * 1.9

    tooth = 0.5 + 0.5 * np.sin(2.0 * np.pi * 94.0 * t)
    grind = bandpass(noise(m), 350.0, 4200.0) * (0.45 + 0.55 * tooth) * 0.55
    grind += bandpass(noise(m), 60.0, 260.0) * 0.18        # the cut loading the motor

    motor = 0.16 * saturate(
        np.sin(2.0 * np.pi * 118.0 * t) + 0.5 * np.sin(2.0 * np.pi * 236.0 * t), 1.6)

    wobble = 1.0 + 0.08 * np.sin(2.0 * np.pi * 6.7 * t) + 0.05 * np.sin(2.0 * np.pi * 2.3 * t)
    return crossfade_loop((blade + grind + motor) * wobble, n, fade_ms=80.0)


def flame_loop():
    """A jet burner running. Three bands, and the low one is the one that matters.

    Real fire is broadband noise whose ENVELOPE is low frequency noise: the roar is
    the flame front moving, not a filter sweep. So the rumble band is modulated by
    a slow random envelope, the mid band by a faster one, and the hiss at the top is
    the gas leaving the nozzle and is almost steady. Exactly periodic throughout,
    because every layer including the envelopes is frequency-domain noise.
    """
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    def env(lo, hi, depth):
        e = periodic_noise(n, lo, hi, tilt=-6.0)
        e = e / (np.max(np.abs(e)) + 1e-9)
        return 1.0 + depth * e

    rumble = periodic_noise(n, 45.0, 260.0, tilt=-2.0) * env(0.5, 7.0, 0.85) * 0.70
    body = periodic_noise(n, 260.0, 1800.0, tilt=-3.0) * env(2.0, 18.0, 0.65) * 0.95
    hiss = periodic_noise(n, 1800.0, 11000.0, tilt=-4.0) * env(6.0, 40.0, 0.30) * 0.55
    # The nozzle itself has a resonance; it is what makes a jet sound like a jet
    # rather than like wind.
    nozzle = modal_periodic(periodic_noise(n, 100.0, 4000.0) * 0.3,
                            [196.0, 412.0, 838.0], [0.5, 0.3, 0.15],
                            [0.012, 0.008, 0.005])
    return saturate(rumble + body + hiss + 0.6 * nozzle, 1.1)


def grinder_loop():
    """The arena grinder disc: a big induction motor, the disc's own ring excited by
    the drive, and the rumble of the housing. Exactly periodic."""
    dur = 1.50
    n = int(dur * SR)
    t = np.arange(n) / SR

    motor = np.zeros(n)
    for f, amp in ((40, 1.0), (80, 0.55), (120, 0.30), (200, 0.14), (280, 0.08)):
        motor += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    motor = saturate(motor * 0.7, 1.6)

    # The disc rings quietly all the time, driven by the bearing hash.
    hash_ = periodic_noise(n, 400.0, 9000.0, tilt=-2.5)
    disc = modal_periodic(hash_ * 0.25,
                          [742.0, 1188.0, 1893.0, 2761.0, 4102.0],
                          [1.0, 0.6, 0.38, 0.22, 0.12],
                          [0.090, 0.065, 0.045, 0.030, 0.020]) * 0.55
    rumble = 0.35 * periodic_noise(n, 30.0, 180.0, tilt=-4.0)
    return (motor + disc + rumble + 0.18 * hash_) * lfo(t, [2.0, 6.0], [0.05, 0.03], dur)


def disc_spin_loop():
    """A heavy free-spinning disc (the Coliseum's, and a spinner at rest speed):
    almost all air and bearing, very little motor, because nothing is driving it."""
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    wash = 0.5 + 0.5 * np.sin(2.0 * np.pi * 26 * t)          # the disc passing
    air = periodic_noise(n, 140.0, 5200.0, tilt=-3.5) * (0.4 + 0.6 * wash)
    bearing = np.zeros(n)
    for f, amp in ((313, 0.35), (626, 0.18), (939, 0.09)):
        bearing += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    bearing *= lfo(t, [13.0], [0.4], dur)
    rumble = 0.30 * periodic_noise(n, 28.0, 150.0, tilt=-5.0)
    return air * 0.8 + bearing + rumble


# ---------------------------------------------------------------- hazards

def pit_open():
    """The Drop Zone's floor giving way: hydraulics take the weight, a warning
    klaxon-free mechanical groan, the leaves sliding, then the stop at full open."""
    dur = 1.100
    n = int(round(dur * SR))
    t = np.arange(n) / SR

    # Hydraulic groan: low tone sliding up as pressure builds, saturated.
    f = 52.0 + 30.0 * np.clip(t / 0.55, 0, 1) ** 0.7
    groan = saturate(np.sin(2.0 * np.pi * np.cumsum(f) / SR)
                     + 0.45 * np.sin(2.0 * np.pi * np.cumsum(f * 3) / SR), 1.9)
    groan *= np.clip(t / 0.07, 0, 1) * (1.0 - np.clip((t - 0.72) / 0.18, 0, 1)) * 0.7

    # Steel leaves sliding on steel: broadband scrape with a moving resonance.
    slide_env = np.clip((t - 0.08) / 0.12, 0, 1) * (1.0 - np.clip((t - 0.70) / 0.16, 0, 1))
    scrape = modal(bandpass(noise(n), 300.0, 7000.0) * 0.5 * slide_env,
                   [640.0, 1072.0, 1734.0], [1.0, 0.55, 0.3],
                   [0.010, 0.007, 0.005]) * 0.8

    # Stop: two heavy leaves hitting their end plates a few ms apart.
    out = groan + scrape
    for off, g, f0 in ((0.760, 1.0, 126.0), (0.792, 0.7, 141.0)):
        i = int(off * SR)
        seg = hit(dur - off, f0, [0.120, 0.092, 0.068, 0.046, 0.031],
                  strike_ms=1.6, strike_hi=4500.0,
                  thump_f=58.0, thump_tau=0.11, thump_gain=1.4)
        out[i:i + len(seg)] += g * seg
    return out


def flame_jet():
    """Ignition: the gas valve, a soft whump as it catches, then the roar arriving.
    A one shot; `flame_loop` takes over underneath it while the jet is firing."""
    dur = 0.700
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    click = np.zeros(n)
    c = hit(0.030, 1180.0, [0.008, 0.006, 0.004], strike_ms=0.25, strike_hi=11000.0)
    click[:len(c)] += 0.45 * c
    # The whump: a burst of low energy as the gas volume catches all at once.
    whump = lowpass(noise(n), 260.0) * np.clip((t - 0.030) / 0.012, 0, 1) \
        * decay(np.maximum(t - 0.030, 0), 0.085) * 1.6
    onset = np.clip((t - 0.045) / 0.09, 0, 1)
    roar = (bandpass(noise(n), 60.0, 900.0) * 0.9 + bandpass(noise(n), 900.0, 7000.0) * 0.35)
    roar *= onset * (0.75 + 0.25 * np.sin(2.0 * np.pi * 7.0 * t))
    tail = 1.0 - np.clip((t - 0.52) / 0.17, 0, 1)
    return (click + whump + roar) * tail


def ram_crush():
    """The Crush arena's wall stroke landing. The biggest impact in the game, so it
    is the only one with a real sub layer and a room-sized tail of rattling."""
    dur = 0.850
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = hit(dur, 162.0, [0.210, 0.165, 0.124, 0.090, 0.062, 0.042],
               strike_ms=2.2, strike_hi=3900.0)
    # The one sound in the game allowed a real sub layer, and even here it is kept
    # under the body: the Crush wall must SOUND the heaviest, not measure it.
    f = 66.0 * (0.6 + 0.4 * decay(t, 0.070))
    sub = 0.68 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.170)
    crack = 0.6 * bandpass(noise(n), 500.0, 5500.0) * decay(t, 0.010)
    # Everything not bolted down rattling afterwards.
    rate = 70.0 * np.exp(-t / 0.25) + 14.0
    phase = np.cumsum(rate) / SR
    ticks = np.zeros(n)
    edges = np.where(np.diff(np.floor(phase)) > 0)[0]
    ticks[edges] = RNG.uniform(0.15, 0.6, len(edges))
    rattle = modal(bandpass(ticks, 600.0, 6000.0),
                   [930.0, 1490.0, 2380.0], [1.0, 0.55, 0.3],
                   [0.016, 0.011, 0.008])
    rattle *= np.clip((t - 0.05) / 0.05, 0, 1) * decay(np.maximum(t - 0.05, 0), 0.30)
    return saturate(1.7 * body, 1.2) * decay(t, 0.42) + sub + crack + 0.75 * rattle


def spikes():
    """Floor spikes rising: the ram's air, steel sliding through the floor plate,
    then the tips hitting their top stop."""
    dur = 0.440
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    x = np.zeros(n)
    rise_n = int(0.300 * SR)
    tr = t[:rise_n]
    air = bandpass(noise(rise_n), 900.0, 6000.0) * np.clip(tr / 0.020, 0, 1) * 0.55
    # The scrape is the plate resonating as the shaft drags through it: a modal
    # body driven by friction noise, with the resonance rising as more shaft shows.
    fric = bandpass(noise(rise_n), 200.0, 5000.0) * 0.35 * np.clip(tr / 0.030, 0, 1)
    scrape = np.zeros(rise_n)
    seg = rise_n // 6
    for k in range(6):
        f0 = 240.0 * (1.0 + 0.28 * k)
        piece = modal(fric, [f0, f0 * 1.63, f0 * 2.41], [1.0, 0.5, 0.28],
                      [0.012, 0.009, 0.006])
        w = np.zeros(rise_n)
        a, b = k * seg, min((k + 1) * seg + seg // 2, rise_n)
        w[a:b] = np.hanning(b - a)
        scrape += piece * w
    x[:rise_n] += air + 0.8 * scrape
    at = int(0.296 * SR)
    stop = hit(dur - 0.296, 268.0, [0.038, 0.028, 0.019, 0.013], strike_ms=0.8,
               strike_hi=6500.0, thump_f=96.0, thump_tau=0.030, thump_gain=1.1)
    x[at:at + len(stop)] += 1.4 * stop
    return x


# ---------------------------------------------------------------- ui / fight

def countdown_tick():
    """Dry, hard, no pitch. A small resonant body struck, not a sine: at pitch 1.5
    (which is what FIGHT plays it at) a sine turns into a beep and this does not."""
    dur = 0.090
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = modal(strike(n, 0.3, 12000.0, 600.0),
                 [880.0, 1762.0, 2643.0, 4410.0],
                 [1.0, 0.45, 0.22, 0.10],
                 [0.020, 0.014, 0.009, 0.005])
    return body * decay(t, 0.026)


def ko_tick():
    """The knockout count. Dull, close, urgent: a low body with the top rolled off,
    so that when fx pitches it up 3.5 % per second it tightens rather than sparkles."""
    dur = 0.140
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    body = modal(strike(n, 1.2, 2600.0, 120.0),
                 [300.0, 452.0, 741.0, 1180.0],
                 [1.0, 0.5, 0.22, 0.10],
                 [0.038, 0.028, 0.018, 0.011])
    thump = 0.7 * np.sin(2.0 * np.pi * 96.0 * t) * decay(t, 0.030)
    return body * decay(t, 0.042) + thump


def bell():
    """The ring bell: struck, long, and with the beat a real bell has.

    Built as a modal bank driven by a hammer click, so the strike noise is coloured
    BY the bell rather than added to it. Each partial has a detuned twin (the two
    degenerate modes of any nearly-axisymmetric shell), which is what produces the
    slow warble, and the hum note an octave below the prime is what makes it read
    as heavy metal rather than as a chime.
    """
    dur = 2.60
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    f0 = 523.0
    ratios = [0.50, 1.00, 1.18, 1.50, 2.00, 2.53, 3.01, 4.12, 5.43, 6.81]
    amps = [0.62, 1.00, 0.60, 0.46, 0.38, 0.25, 0.19, 0.11, 0.07, 0.04]
    taus = [1.70, 1.25, 0.85, 0.68, 0.48, 0.33, 0.25, 0.15, 0.10, 0.07]
    freqs, a_all, t_all = [], [], []
    for r, a, tau in zip(ratios, amps, taus):
        freqs += [f0 * r, f0 * r * 1.0018]
        a_all += [a, a * 0.72]
        t_all += [tau, tau * 0.95]
    exc = strike(n, ms=0.9, hi=9000.0, lo=300.0)
    x = modal(exc, freqs, a_all, t_all)
    x += 0.30 * bandpass(exc, 2000.0, 11000.0) * 6.0     # the hammer itself
    return x


def crowd_ambience_loop():
    """8 s seamless STEREO arena hall: distant crowd and PA room tone.

    No recognisable words, and structurally incapable of having any: the crowd is
    band limited noise whose only movement is slow amplitude modulation, with no
    formant motion and nothing above a 4 Hz envelope, so there is no speech-shaped
    content to hear words in. Three parts:

    1. MURMUR: a 200 to 1800 Hz band at -3 dB/octave (the average of several
       hundred voices is pink, not white), gently swelled by very slow envelopes,
       plus a quieter 1.8 to 5 kHz band for the room's air.
    2. SWELLS: two broad rises per loop, well under the murmur, so the hall
       breathes instead of sitting flat. They are at 1/8 and 2/8 Hz, so they loop.
    3. PA ROOM TONE: 50 Hz mains hum and its harmonics, 40 dB down, plus the
       preamp hiss of a live system with nothing going through it.

    Every layer is frequency-domain noise or a whole number of cycles per loop, and
    the room is applied by CIRCULAR convolution, so the file is exactly periodic:
    there is no crossfade and no fade, and the seam is sample accurate.

    Stereo is two independent noise fields sharing one envelope, which decorrelates
    the sides (a wide hall) while keeping the crowd's movement mono-compatible.
    """
    dur = 8.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    def side():
        murmur = periodic_noise(n, 200.0, 1800.0, tilt=-3.0)
        murmur *= lfo(t, [0.25, 0.625, 1.375, 2.5], [0.16, 0.11, 0.07, 0.04], dur)
        air = 0.22 * periodic_noise(n, 1800.0, 5200.0, tilt=-4.5)
        air *= lfo(t, [0.375, 1.125], [0.12, 0.08], dur)
        swell = lfo(t, [0.125, 0.25], [0.22, 0.12], dur) - 1.0
        body = murmur * (1.0 + 0.5 * swell) + air
        # PA: mains hum, 40 dB down, plus the hiss of an idle system.
        pa = np.zeros(n)
        for f, amp in ((50, 1.0), (100, 0.45), (150, 0.25), (250, 0.08)):
            pa += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
        pa = pa * 0.010 + 0.022 * periodic_noise(n, 800.0, 14000.0, tilt=-1.0)
        wet = circular_reverb(body, decay_s=0.85, pre_ms=14.0, hf_damp=3200.0)
        wet /= np.max(np.abs(wet)) + 1e-9
        return 0.55 * body + 0.75 * wet + pa

    left = side()
    right = side()
    # A touch of correlation in the low end keeps the hall from sounding like two
    # different rooms; the mids and highs stay independent.
    lo_l = lowpass(np.tile(left, 3), 220.0)[n:2 * n]
    lo_r = lowpass(np.tile(right, 3), 220.0)[n:2 * n]
    mid = 0.5 * (lo_l + lo_r)
    left = left - lo_l + mid
    right = right - lo_r + mid
    return np.stack([left, right], axis=1)


# ================================================================ main


def build_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Roboteer sounds -> %s\n" % OUT_DIR)

    print("-- feedback ------------------------------------------------")
    write("bolt_collect.wav", bolt_collect(), in_ms=0.2, out_ms=3.0)
    for i in range(3):
        write("impact_light_%d.wav" % (i + 1), impact_light(i), in_ms=0.2, out_ms=6.0)
    for i in range(3):
        write("impact_heavy_%d.wav" % (i + 1), impact_heavy(i), in_ms=0.2, out_ms=14.0)

    print("\n-- weapons -------------------------------------------------")
    write("flipper_fire.wav", flipper_fire(), in_ms=0.5, out_ms=14.0)
    write("axe_swing.wav", axe_swing(), in_ms=3.0, out_ms=14.0)
    write("axe_hit.wav", axe_hit(), in_ms=0.2, out_ms=16.0)
    write("ram_hit.wav", ram_hit(), in_ms=0.2, out_ms=16.0)
    write("crusher_clamp.wav", crusher_clamp(), in_ms=3.0, out_ms=20.0)

    print("\n-- parts coming off ----------------------------------------")
    write("wheel_off.wav", wheel_off(), in_ms=0.3, out_ms=16.0)
    write("panel_off.wav", panel_off(), in_ms=0.3, out_ms=16.0)

    print("\n-- loops ---------------------------------------------------")
    write("motor_loop.wav", motor_loop(), loop=True)
    write("spin_up_loop.wav", spin_up_loop(), loop=True)
    write("saw_cut_loop.wav", saw_cut_loop(), loop=True)
    write("flame_loop.wav", flame_loop(), loop=True)
    write("grinder_loop.wav", grinder_loop(), loop=True)
    write("disc_spin_loop.wav", disc_spin_loop(), loop=True)

    print("\n-- arena hazards -------------------------------------------")
    write("spikes.wav", spikes(), in_ms=1.0, out_ms=14.0)
    write("pit_open.wav", pit_open(), in_ms=2.0, out_ms=20.0)
    write("flame_jet.wav", flame_jet(), in_ms=0.3, out_ms=20.0)
    write("ram_crush.wav", ram_crush(), in_ms=0.2, out_ms=24.0)

    print("\n-- fight and UI --------------------------------------------")
    write("countdown_tick.wav", countdown_tick(), in_ms=0.3, out_ms=6.0)
    write("ko_tick.wav", ko_tick(), in_ms=0.3, out_ms=8.0)
    write("bell.wav", bell(), in_ms=0.3, out_ms=60.0)

    print("\n-- ambience ------------------------------------------------")
    write("crowd_ambience_loop.wav", crowd_ambience_loop(), loop=True)

    print("\n%d files, %.2f s of audio" % (len(_REPORT), sum(r[1] for r in _REPORT)))
    print("\nNow run:")
    print("  ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import")
    print("  python3 scripts/gen-sounds.py --patch-imports")


def patch_imports():
    """Set loop forward + PCM on every loop's .import, and PCM on bolt_collect.

    Godot's WAV importer defaults to loop_mode=0 and compress/mode=2 (QOA, lossy).
    A lossy codec smears the loop seam into an audible tick once per revolution,
    and without loop_mode the motor hum restarts instead of looping. Both settings
    are written into the .import file, which is committed, so this only has to be
    run when a NEW file has just been imported for the first time.

    bolt_collect is PCM as well: it is 45 ms and is pitched up to two octaves by
    the collect ramp, which is exactly the case where a lossy codec's high band
    artefacts become audible.
    """
    pcm_only = LOOPS + ["bolt_collect.wav"]
    touched = 0
    for name in sorted(os.listdir(OUT_DIR)):
        if not name.endswith(".wav.import"):
            continue
        wav = name[:-len(".import")]
        path = os.path.join(OUT_DIR, name)
        with open(path) as fh:
            text = fh.read()
        out = text
        want_loop = "2" if wav in LOOPS else "0"
        want_compress = "0" if wav in pcm_only else "2"
        out = re.sub(r"^edit/loop_mode=.*$", "edit/loop_mode=" + want_loop,
                     out, flags=re.MULTILINE)
        out = re.sub(r"^compress/mode=.*$", "compress/mode=" + want_compress,
                     out, flags=re.MULTILINE)
        if out != text:
            with open(path, "w") as fh:
                fh.write(out)
            touched += 1
            print("  patched %-30s loop=%s compress=%s" % (name, want_loop, want_compress))
    print("%d .import files patched" % touched)
    if touched:
        print("Re-run the Godot --import so the .sample binaries are rebuilt.")


def main():
    if "--patch-imports" in sys.argv:
        patch_imports()
        return 0
    build_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
