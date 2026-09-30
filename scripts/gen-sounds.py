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
import zlib

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
PEAK_DBFS = -3.0
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "Arena", "audio")

# THE SEED, and why every sound now gets its OWN stream off it.
#
# Until wave F this was one generator consumed in call order, which made the script
# reproducible and made it a trap: changing any sound changed the draws every sound
# after it got, so a one line edit to the ambience rewrote the two endgame cues as
# well. (Agent G6 worked around it by appending its two builds at the end of
# build_all and saying so in a comment.) Wave F had to rebuild `bolt_collect` and
# `crowd_ambience_loop`, which sit in the MIDDLE, so the trap was removed instead of
# worked around: `build()` re-seeds RNG per file name, from this seed and a CRC of
# the name. A file's bytes now depend on its own builder and nothing else, sounds can
# be added or changed anywhere in the list, and a re-run is still byte identical.
#
# One-time cost, paid in wave F: every file's noise realisation changed once, because
# the stream each of them draws from is a different one. Nothing about the DESIGN of
# any of them changed; the peaks, lengths, loop seams and spectra were all re-measured
# afterwards (docs/wave-f-f2-notes.md).
STREAM_SEED = 20260913
RNG = np.random.default_rng(STREAM_SEED)

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
    "endgame_drone_loop.wav",
    # wave F (F2): the movement layer.
    "drive_whine_loop.wav",
    "roll_wheel_loop.wav",
    "track_clatter_loop.wav",
    "roll_omni_loop.wav",
    "skid_loop.wav",
    "scrape_loop.wav",
    # wave P (F): the six weapons, the three drives and the fire patch.
    "arc_crackle_loop.wav",
    "drill_grind_loop.wav",
    "twin_saw_loop.wav",
    "fire_patch_loop.wav",
    "vortex_spin_loop.wav",
    "hover_fan_loop.wav",
    "hover_skirt_loop.wav",
    "leg_servo_loop.wav",
    "adaptive_track_loop.wav",
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


def build(name, fn, *args, **kw):
    """Render one sound on its OWN seeded stream, then write it.

    The stream is seeded from STREAM_SEED and a CRC of the file name, so the bytes of
    any one file depend only on its builder and its name. See STREAM_SEED above for
    why that matters.
    """
    global RNG
    RNG = np.random.default_rng([STREAM_SEED, zlib.crc32(name.encode("utf-8"))])
    return write(name, fn(*args), **kw)


# ================================================================ the sounds
#
# Every function returns a float array at any scale; `write` normalises.


# ---------------------------------------------------------------- collect

def bolt_collect():
    """55 ms. A shorn steel nut landing in a STEEL BIN, which is what the scrap
    counter is, and not the chime it used to be.

    The first build was six high, tightly damped modes starting at 1760 Hz and
    nothing at all below 900 Hz: measured centroid 2596 Hz, 47 % of its energy above
    2 kHz. That is a triangle, not a bolt. What makes a small piece of steel landing
    in a bin sound like a small piece of steel landing in a bin is that you hear the
    BIN: a big thin panel, struck off centre, ringing for 30-odd milliseconds an
    octave and a half below the nut itself, with a hard broadband tick on top and a
    single little bounce a few milliseconds later.

    So there are three parts now: the tick (a 0.3 ms strike, still bright, because
    the leading edge is what cuts through), the NUT (high modes, 4 ms decay - the
    object is small, so it is over almost at once), and the PANEL (a thin steel
    sheet at 380 Hz with the inharmonic mode set of a plate, 35 ms). Then the same
    strike again at 9 ms into the SAME buffer, so the modes still ringing from the
    first arrival are added to by the second: one nut bouncing, not two nuts.

    It still has to survive the collect ramp, which pitches it up two octaves
    (`CollectAudio`, brief-v3 §6): at pitch 4.0 the panel is at 1520 Hz, which is
    well inside where it still reads as metal, and the whole file is 14 ms long.
    The pitch SPREAD is untouched - this is a new sample under the same ramp.
    """
    n = int(0.055 * SR)
    t = np.arange(n) / SR

    def arrival(at_s, gain, hi):
        """One contact, written into the shared buffer at `at_s`."""
        e = np.zeros(n)
        k = max(int(SR * 0.30 / 1000.0), 2)
        i = int(at_s * SR)
        if i + k < n:
            e[i:i + k] = noise(k) * np.hanning(k * 2)[:k][::-1] * gain
        return bandpass(e, 260.0, hi)

    exc = arrival(0.0, 1.0, 13000.0) + arrival(0.009, 0.42, 9000.0)

    # The bin: a thin steel panel, plate modes, struck off centre.
    panel = modal(
        exc,
        steel_modes(380.0, count=6),
        [1.0, 0.72, 0.52, 0.36, 0.24, 0.15],
        [0.035, 0.026, 0.019, 0.014, 0.010, 0.007],
    )
    # The nut itself: small, high, over in four milliseconds.
    nut = modal(
        exc,
        [1740.0, 2830.0, 3910.0, 5260.0],
        [1.0, 0.66, 0.44, 0.26],
        [0.0042, 0.0031, 0.0023, 0.0016],
    )
    tick = 0.55 * highpass(exc, 4500.0)
    return panel * decay(t, 0.030) + 0.62 * nut + tick


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


# ---------------------------------------------------------------- hazard warnings (wave A)
#
# One shared warning language (docs/wave-a-hazards-notes.md): every timed hazard in the
# game plays its OWN wind-up exactly WARN_LEAD_S (1.25 s) before it acts, so the player
# learns one rhythm and six sounds. Each file is 1.20 s long and is built to END on the
# activation: the rise in pitch, rate or level lands on the frame the hazard's own
# one-shot (`spikes`, `flame_jet`, `ram_crush`, `pit_open`) takes over.

def warn_spikes():
    """1.20 s. The Yard's spike patch charging: a compressor pumping up (a ratchet of
    valve clicks that speeds up from 6 to 22 a second) over rising air, and the
    pressure-relief chirp on the last beat."""
    dur = 1.20
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    k = np.clip(t / dur, 0, 1)
    rate = 6.0 + 16.0 * k ** 1.6
    phase = np.cumsum(rate) / SR
    clicks = np.zeros(n)
    edges = np.where(np.diff(np.floor(phase)) > 0)[0]
    clicks[edges] = 0.6 + 0.4 * k[edges]
    valve = modal(bandpass(clicks, 700.0, 9000.0), steel_modes(1650.0, count=4),
                  [1.0, 0.55, 0.3, 0.15], [0.010, 0.007, 0.005, 0.003]) * 1.4
    air = bandpass(noise(n), 1500.0, 8000.0) * (0.08 + 0.42 * k ** 2)
    # The plate under the patch taking the pressure: a low body that swells.
    f = 210.0 + 60.0 * k
    body = 0.25 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * k ** 1.5
    return valve + air + saturate(body, 1.3)


def warn_flame():
    """1.20 s. A gas nozzle arming: the supply valve opening into a hiss that rises,
    and the piezo igniter clicking faster and faster (4 to 18 a second) until it
    catches, which is where `flame_jet`'s whump takes over."""
    dur = 1.20
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    k = np.clip(t / dur, 0, 1)
    thunk = np.zeros(n)
    th = hit(0.12, 420.0, [0.030, 0.022, 0.015], strike_ms=0.6, strike_hi=5000.0)
    thunk[:len(th)] += 0.55 * th
    hiss = (bandpass(noise(n), 1800.0, 9500.0) * 0.8 + bandpass(noise(n), 300.0, 1800.0) * 0.3)
    hiss *= np.clip(t / 0.06, 0, 1) * (0.15 + 0.65 * k ** 1.4)
    rate = 4.0 + 14.0 * k ** 1.5
    phase = np.cumsum(rate) / SR
    sparks = np.zeros(n)
    edges = np.where(np.diff(np.floor(phase)) > 0)[0]
    sparks[edges] = 1.0
    snap = modal(highpass(sparks, 2000.0), [4100.0, 6300.0, 8800.0], [1.0, 0.6, 0.35],
                 [0.004, 0.003, 0.002]) * 1.6
    return thunk + hiss + snap


def warn_ram():
    """1.20 s. The Crush's hydraulics loading up: the pump motor spinning up (its
    fundamental climbs 220 to 520 Hz, saturated so it survives a phone speaker), the
    relief valve chattering over it, and the pressure groan in the housing."""
    dur = 1.20
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    k = np.clip(t / dur, 0, 1)
    f = 220.0 + 300.0 * k ** 1.3
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    whine = saturate(np.sin(ph) + 0.5 * np.sin(2.0 * ph) + 0.3 * np.sin(3.0 * ph), 2.2)
    whine *= (0.25 + 0.75 * k) * np.clip(t / 0.05, 0, 1)
    chatter = bandpass(noise(n), 900.0, 4000.0) * (0.5 + 0.5 * np.sign(np.sin(2.0 * np.pi * (9.0 + 12.0 * k) * t)))
    chatter *= 0.18 * k ** 2
    groan = modal(bandpass(noise(n), 150.0, 700.0) * 0.4, [231.0, 347.0, 522.0],
                  [1.0, 0.5, 0.3], [0.03, 0.02, 0.015]) * k
    groan *= 0.25 / (np.max(np.abs(groan)) + 1e-9)
    return 0.8 * whine + chatter + groan


def warn_pit():
    """1.20 s. The Drop Zone's klaxon: a reed horn on two tones a tritone apart, three
    blasts, the last one held into the leaves moving."""
    dur = 1.20
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    out = np.zeros(n)
    for start, length, f0 in ((0.00, 0.30, 311.0), (0.38, 0.30, 440.0), (0.76, 0.44, 311.0)):
        a = int(start * SR)
        m = min(int(length * SR), n - a)
        tt = np.arange(m) / SR
        ph = 2.0 * np.pi * f0 * tt
        buzz = np.zeros(m)
        for h in range(1, 14):
            buzz += np.sin(h * ph) / h
        buzz = saturate(buzz, 1.6)
        # Two bore formants, so it is a horn and not a square wave.
        horn = bandpass(buzz, 500.0, 1400.0) * 0.9 + bandpass(buzz, 1900.0, 3200.0) * 0.4
        env = np.clip(tt / 0.02, 0, 1) * (1.0 - np.clip((tt - (length - 0.04)) / 0.04, 0, 1))
        out[a:a + m] += horn * env
    return out


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


# ---------------------------------------------------------------- endgame (wave G, G6)


def endgame_horn():
    """Brief v4 §2: the horn at 2:00. One shot, and the loudest announcement in the
    game after the bell, because the moment it marks has to be unmissable.

    Built as an air horn really works rather than as a synth chord: a reed buzzing
    into a flaring bore. The excitation is a 1/k harmonic stack soft clipped into a
    buzz (a reed does not make a sine, it slams open and shut), and the bore is two
    broad formants around 380 to 3200 Hz and 700 to 1500 Hz, which is the part that
    makes it a horn and not a doorbell. Three details do the rest:

      - a PITCH SCOOP of 7 % over the first 25 ms, because the air column takes that
        long to catch. Without it the note starts already in tune and reads as a
        sample being triggered;
      - TWO TONES a fourth apart (F3 and A#3, the interval a road horn uses). Their
        beating is what a single tone can never fake;
      - the reservoir SAGGING 14 % after the first blast, then the valve shutting.

    Deliberately thin below 200 Hz: the formants cut the fundamentals, so this lands
    on a phone speaker (docs/audio-notes.md §4) instead of disappearing into it.
    """
    dur = 1.80
    n = int(round(dur * SR))
    t = np.arange(n) / SR

    scoop = 1.0 - 0.07 * decay(t, 0.024)
    env = np.clip(t / 0.018, 0.0, 1.0)
    env = env * np.where(t < 1.05, 1.0, np.exp(-(t - 1.05) / 0.20))
    env = env * (0.86 + 0.14 * decay(t, 0.18))

    out = np.zeros(n)
    for f0, gain in ((174.61, 1.00), (233.08, 0.82)):
        phase = 2.0 * np.pi * np.cumsum(f0 * scoop) / SR
        buzz = np.zeros(n)
        for k in range(1, 13):
            if f0 * k > SR * 0.45:
                break
            buzz += np.sin(k * phase) / k
        buzz = saturate(buzz * 1.6, drive=2.2)
        out += gain * (bandpass(buzz, 380.0, 3200.0) + 0.45 * bandpass(buzz, 700.0, 1500.0))

    # The valve itself: a short metal tick, so the blast has something to start on.
    valve = modal(strike(n, 0.4, 7000.0, 900.0),
                  [1180.0, 1970.0, 3010.0], [1.0, 0.5, 0.25],
                  [0.012, 0.008, 0.005]) * 0.45
    # Air through the nozzle: loud for a moment, then a thin hiss riding the note.
    air = bandpass(noise(n), 1200.0, 7000.0) * (0.30 * decay(t, 0.03) + 0.05)
    return (out + air) * env + valve * np.clip(t / 0.002, 0.0, 1.0)


def endgame_drone_loop():
    """The last minute, under everything. Brief v4 §10 item 2 asks for a music cue at
    the endgame; this is it, and it is deliberately not a tune.

    A tune would have to end, or loop audibly, or fight the impacts for the same
    midrange the fight lives in. This is a drone on a fifth with ONE PULSE A SECOND
    over it: a heartbeat under the crowd rather than music on top of it. It plays on
    the Music bus, which has been wired and empty since Stage 6, at -22 dB.

    Pitched at 110 Hz, NOT at the 55 Hz a drone wants to be. The first build was a
    sub drone and measured 98.3 % of its energy below 200 Hz, which on a phone
    speaker (docs/audio-notes.md §4: effectively gone below ~400 Hz) is an endgame
    music cue nobody can hear. The weight now sits on the 220 / 330 / 440 partials
    and the pulse is a 200 to 1500 Hz swell, so it survives the device; the 55 Hz
    octave is kept underneath for headphones and for the hand.

    Exactly periodic by construction, like the ambience bed: every partial is a
    whole number of cycles per loop (110 x 4 = 440), the pulse is at 1 Hz (4 per
    loop) and starts from zero, the noise is frequency domain noise and the final
    lowpass is run circularly. So there is no crossfade and no seam.
    """
    dur = 4.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    drone = np.zeros(n)
    for f, a in ((55.0, 0.35), (110.0, 1.00), (165.0, 0.55), (220.0, 0.65),
                 (330.0, 0.35), (440.0, 0.18)):
        drone += a * np.sin(2.0 * np.pi * f * t + RNG.uniform(0.0, 2.0 * np.pi))
    drone = saturate(drone * 0.8, drive=1.6)
    drone *= lfo(t, [0.25, 0.5], [0.10, 0.06], dur)

    # One pulse a second, zero at the wrap. ^5 turns the raised cosine into a swell
    # with a shape, rather than a tremolo.
    beat = (0.5 - 0.5 * np.cos(2.0 * np.pi * 1.0 * t)) ** 5
    pulse = 0.55 * periodic_noise(n, 200.0, 1500.0, tilt=-6.0) * beat
    pulse += 0.40 * np.sin(2.0 * np.pi * 220.0 * t) * beat

    x = 0.75 * drone + pulse
    return circular_filter(x, lambda y: lowpass(y, 1500.0))


# ================================================================ wave F (F2)
#
# Movement, the crowd and the bin. Everything below is agent F2's (wave F), added
# because the owner played wave G on his iPhone and said: "I can't hear the crowd
# properly, there are no movement noises". docs/wave-f-f2-notes.md has the levels.
#
# The phone-speaker rule (docs/audio-notes.md §4) drives every design choice here:
# a small speaker is effectively gone below about 200 Hz and does its best work
# between 700 Hz and 6 kHz, so a movement layer written as low rumble is a movement
# layer nobody on a phone will ever hear. Every loop below is written with its
# weight in the band a phone can actually move air with, and the sub content is
# there for headphones only.


# ---------------------------------------------------------------- loop helpers


def impulse_train(n, rate_hz, ms=0.6, hi=9000.0, lo=300.0, jitter=0.0,
                  gain_spread=0.0):
    """An EXACTLY PERIODIC train of short strikes: the excitation for anything that
    hits something once per revolution (a track link, an omni roller, a tread block).

    `rate_hz` must divide evenly into the loop (rate_hz * dur a whole number) or the
    train will not wrap. Strikes are placed with a modulo, so a kernel that runs off
    the end continues at the start, which is what a genuinely continuous recording
    would have done there.
    """
    n = int(n)
    out = np.zeros(n)
    step = SR / float(rate_hz)
    count = int(round(n / step))
    k = max(int(SR * ms / 1000.0), 2)
    for i in range(count):
        at = int(round(i * step + (RNG.uniform(-jitter, jitter) * step if jitter > 0 else 0.0)))
        g = 1.0 + (RNG.uniform(-gain_spread, gain_spread) if gain_spread > 0 else 0.0)
        kern = noise(k) * np.hanning(k * 2)[:k][::-1] * g
        idx = (np.arange(k) + at) % n          # wrap, so the loop stays seamless
        out[idx] += kern
    return circular_filter(out, lambda z: bandpass(z, lo, hi))


def burst_gate(t, rate_hz, dur, duty=0.5, depth=1.0, shape=2.0):
    """Stick-slip: a periodic gate that snaps rather than swings.

    Rubber scrubbing and steel dragging are both stick-slip processes; the ear hears
    the RATE of the slip, not a tremolo. `rate_hz * dur` must be a whole number.
    """
    k = max(round(rate_hz * dur), 1)
    phase = (k / dur) * t
    saw = phase - np.floor(phase)
    g = np.clip((duty - saw) / max(duty, 1e-3), 0.0, 1.0) ** (1.0 / shape)
    return 1.0 - depth + depth * g


def room(x, decay_s=0.9, pre_ms=12.0, hf_damp=3600.0):
    """A hall for a ONE SHOT. `circular_reverb` wraps its tail into the head, which
    is right for a loop and pre-echo for a one shot, so the signal is zero padded by
    the length of the tail first and the wrap lands in the padding.
    """
    n = len(x)
    m = int(decay_s * 3.0 * SR)
    y = np.zeros(n + m)
    y[:n] = x
    return circular_reverb(y, decay_s, pre_ms, hf_damp)


def _slow(n, hz):
    """A unit-scaled sub-audio wander: the crowd's own surge, at a few hertz.

    It is a lowpass on noise rather than a bandpass, because a bandpass with a corner
    under 20 Hz is not a filter this script can build, and because DC in a multiplier
    is exactly the constant term that belongs there.
    """
    x = lowpass(noise(int(n)), hz, order=2)
    return x / (np.max(np.abs(x)) + 1e-9)


def clap_field(n, density_env, ms=2.6, lo=900.0, hi=7500.0, wrap=True):
    """Hands, not voices.

    A crowd read on a phone speaker is mostly CLAPS: broadband 1-6 kHz transients,
    which is exactly the band a small speaker reproduces best, and exactly the band
    the old ambience bed had almost nothing in (2.9 % above 2 kHz, measured).

    `density_env` is claps per second at each sample. Every clap is a filtered noise
    burst with a hard attack, so there is no formant motion anywhere in the layer and
    therefore nothing for the ear to resolve into words (docs/audio-notes.md §3).
    """
    n = int(n)
    out = np.zeros(n)
    k = max(int(SR * ms / 1000.0), 3)
    env = np.asarray(density_env, dtype=np.float64)
    if env.ndim == 0:
        env = np.full(n, float(env))
    # Thin a uniform candidate grid by the local density: a Poisson process without
    # having to draw inter-arrival times.
    grid = max(int(SR / 400.0), 1)
    cand = np.arange(0, n, grid)
    keep = RNG.uniform(0.0, 1.0, len(cand)) < (env[cand] * grid / SR)
    for at in cand[keep]:
        tt = np.arange(k) / SR
        kern = noise(k) * np.exp(-tt / 0.0016) * RNG.uniform(0.45, 1.0)
        idx = ((np.arange(k) + at) % n) if wrap else np.clip(np.arange(k) + at, 0, n - 1)
        out[idx] += kern
    f = circular_filter if wrap else (lambda z, fn: fn(z))
    return f(out, lambda z: bandpass(z, lo, hi))


# ---------------------------------------------------------------- movement loops


def drive_whine_loop():
    """1 s seamless. THE motor sound of a machine that is moving, and the one the
    game was missing: `motor_loop.wav` exists but nothing ever called
    `set_motor_state`, and even if it had, 68 % of that file's energy is below
    200 Hz (measured), so a phone would have played silence.

    This is the same object written for a small speaker. A brushed motor's noise is
    commutation (the brushes making and breaking, at the bar rate) and gear mesh (a
    tooth rate tone with harmonics, amplitude modulated once per shaft revolution
    because no reduction box is concentric). Both of those live in the mid band.
    The 55 Hz armature hum is still underneath at a tenth of the level, for
    headphones.

    Written LOW in its range (mesh at 500 Hz) because `MachineAudio` pitches it up
    to 1.9 with speed, and anything already bright turns into a whistle up there.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    # Gear mesh: the tooth rate and its harmonics, warbling once per revolution.
    mesh = np.zeros(n)
    for f, amp in ((500, 1.0), (1000, 0.46), (1500, 0.22), (2000, 0.11), (2500, 0.05)):
        mesh += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    mesh *= lfo(t, [14.0, 7.0], [0.30, 0.12], dur)

    # Commutation: the brush bar rate, a buzz rather than a tone, band limited to
    # where a phone lives.
    comm = impulse_train(n, 86, ms=0.9, lo=400.0, hi=5200.0, gain_spread=0.12)
    comm = comm / (np.max(np.abs(comm)) + 1e-9)

    # The armature, for headphones. Deliberately a tenth of the level: on a phone
    # this band is inaudible and on headphones it is the weight.
    arm = np.zeros(n)
    for h, amp in ((1, 1.0), (2, 0.5), (3, 0.28)):
        arm += amp * np.sin(2.0 * np.pi * (55 * h) * t + RNG.uniform(0, 2 * np.pi))
    arm = saturate(arm * 0.8, 1.4)

    bearing = periodic_noise(n, 900.0, 7000.0, tilt=-3.0)
    load = lfo(t, [3.0, 11.0], [0.07, 0.04], dur)
    return (0.62 * mesh + 0.40 * comm + 0.10 * arm + 0.14 * bearing) * load


def roll_wheel_loop():
    """1 s seamless. Rubber rolling on a steel arena floor.

    Three things make this noise and none of them is a rumble: the tread blocks
    slapping the plate (an impulse train at the block rate), the contact patch's own
    broadband hiss, and THE FLOOR — a big steel plate rings when something rolls over
    it, which is why the contact noise is run through a modal bank at the plate's
    modes rather than just filtered. `MachineAudio` pitches it with speed, so the
    block rate rises as the machine goes faster, which is what a real tyre does.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    blocks = impulse_train(n, 38, ms=1.0, lo=260.0, hi=6000.0, gain_spread=0.25)
    patch = periodic_noise(n, 320.0, 5200.0, tilt=-2.5)
    patch *= lfo(t, [5.0, 19.0], [0.22, 0.10], dur)

    # The floor plate. Short taus: a bolted-down plate is heavily damped.
    plate = modal_periodic(
        0.45 * blocks + 0.25 * patch,
        steel_modes(430.0, count=6),
        [1.0, 0.70, 0.50, 0.34, 0.22, 0.14],
        [0.026, 0.019, 0.014, 0.010, 0.008, 0.005],
    )
    plate /= np.max(np.abs(plate)) + 1e-9

    # The sub is for headphones only: on a phone this band is gone, so it is written
    # at a level that adds weight there and never sets the peak here.
    rumble = periodic_noise(n, 90.0, 260.0, tilt=-3.0)
    return 0.50 * plate + 0.62 * patch + 0.42 * blocks + 0.10 * rumble


def track_clatter_loop():
    """1.2 s seamless. Tracks, and they are a CLATTER, not a hum.

    A tracked machine's noise is the links: every one of them slaps the ground and
    then slaps the sprocket, so the sound is a hard impulse train through steel, at a
    rate proportional to road speed. Under it, the belt's own rumble and the final
    drive's whine. That impulse train is the whole reason tracks read as tracks and a
    pitched-down wheel loop does not.
    """
    dur = 1.20
    n = int(dur * SR)
    t = np.arange(n) / SR

    # 25 links a second: 30 whole cycles in 1.2 s, so the train wraps exactly.
    links = impulse_train(n, 25, ms=0.8, lo=320.0, hi=9500.0, jitter=0.03,
                          gain_spread=0.35)
    ring = modal_periodic(
        links,
        steel_modes(415.0, count=7),
        [1.0, 0.74, 0.56, 0.40, 0.28, 0.18, 0.11],
        [0.034, 0.025, 0.018, 0.013, 0.009, 0.007, 0.004],
    )
    ring /= np.max(np.abs(ring)) + 1e-9

    # The sprocket, half the link rate because the teeth are every other link.
    sprocket = np.zeros(n)
    for f, amp in ((300, 1.0), (600, 0.40), (900, 0.17)):
        sprocket += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    sprocket *= lfo(t, [5.0], [0.30], dur)

    belt = periodic_noise(n, 160.0, 2400.0, tilt=-2.5) * lfo(t, [10.0], [0.18], dur)
    grit = periodic_noise(n, 1800.0, 9000.0, tilt=-1.5)
    return 0.70 * ring + 0.46 * links + 0.18 * sprocket + 0.30 * belt + 0.30 * grit


def roll_omni_loop():
    """1 s seamless. Omni wheels: a patter, not a roll.

    An omni's tyre is a ring of small free rollers, so instead of one continuous
    contact patch there are dozens of little hard contacts a second. It is higher,
    drier and busier than a tyre and it buzzes when it strafes, which is exactly what
    the drive costs 20 kg and half the push force for.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    rollers = impulse_train(n, 62, ms=0.55, lo=500.0, hi=9500.0, jitter=0.04,
                            gain_spread=0.30)
    snap = modal_periodic(
        rollers,
        steel_modes(540.0, count=6),
        [1.0, 0.62, 0.42, 0.26, 0.16, 0.10],
        [0.012, 0.009, 0.007, 0.005, 0.004, 0.003],
    )
    snap /= np.max(np.abs(snap)) + 1e-9

    hub = periodic_noise(n, 700.0, 6500.0, tilt=-2.5) * lfo(t, [9.0, 23.0], [0.18, 0.09], dur)
    floor = periodic_noise(n, 150.0, 700.0, tilt=-3.0)
    return 0.70 * snap + 0.40 * rollers + 0.30 * hub + 0.16 * floor


def skid_loop():
    """1 s seamless. Rubber scrubbing sideways across steel.

    Stick-slip, and the rate of the slip is the sound: the tyre grips, deflects,
    lets go, grips again, tens of times a second. Modelling that as a gate on
    broadband noise (rather than as a tremolo, which reads as a machine gun) is what
    makes it a skid instead of a hiss. Over it, the squeal: a narrow band that
    wanders, which is the contact patch resonating as the slip angle changes.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    scrub = periodic_noise(n, 380.0, 6500.0, tilt=-2.5)
    scrub *= burst_gate(t, 47, dur, duty=0.62, depth=0.55, shape=1.6)
    scrub *= lfo(t, [3.0, 7.0], [0.16, 0.09], dur)

    # The squeal. One narrow band, wandering, well under the scrub: a loud squeal is
    # a cartoon and this has to sit under a fight for seconds at a time.
    squeal = np.zeros(n)
    for f, amp in ((1180, 1.0), (2360, 0.28), (3540, 0.10)):
        squeal += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    squeal *= 0.5 + 0.5 * lfo(t, [2.0, 5.0], [0.5, 0.3], dur)

    body = modal_periodic(
        0.4 * scrub,
        steel_modes(860.0, count=5),
        [1.0, 0.58, 0.36, 0.22, 0.13],
        [0.018, 0.013, 0.010, 0.007, 0.005],
    )
    body /= np.max(np.abs(body)) + 1e-9
    return 0.80 * scrub + 0.30 * body + 0.10 * squeal


def scrape_loop():
    """1 s seamless. A steel chassis dragging along a steel wall.

    The same stick-slip process as the skid but with no rubber in it: the chatter is
    faster and harder, there is no squeal, and the wall RINGS — the plate's modes are
    excited continuously by the drag, which is the part that makes it read as metal
    on metal rather than as noise. Brighter than the skid on purpose: this is the
    sound that tells the player they are pinned against the boards, and it has to
    survive a phone speaker while a fight is going on.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    drag = periodic_noise(n, 600.0, 11000.0, tilt=-1.5)
    drag *= burst_gate(t, 83, dur, duty=0.55, depth=0.70, shape=2.4)
    drag *= lfo(t, [4.0, 13.0], [0.20, 0.12], dur)

    ring = modal_periodic(
        drag * 0.5,
        steel_modes(470.0, count=7),
        [1.0, 0.74, 0.55, 0.40, 0.28, 0.18, 0.11],
        [0.055, 0.040, 0.030, 0.022, 0.016, 0.011, 0.008],
    )
    ring /= np.max(np.abs(ring)) + 1e-9

    grind = periodic_noise(n, 200.0, 900.0, tilt=-3.0) * burst_gate(t, 19, dur, duty=0.5, depth=0.4)
    return 0.62 * drag + 0.62 * ring + 0.22 * grind


def chassis_thud(variant):
    """0.42 / 0.48 / 0.54 s. A machine landing flat after a flip or a throw.

    Not an impact_heavy: this is 40-odd kilograms of frame arriving on a steel floor
    with everything bolted to it arriving a few milliseconds later. Four layers, in
    this order: the arrival crack, a LOW-MID body (the frame, not a panel, so the
    fundamental is under 200 Hz and saturated), a rubber slap (the tyres, which is a
    fast-decaying low noise and is what stops it ringing like a bell), and the
    RATTLE - every loose panel and the weapon arm, as a burst train that decays.

    Three variants so a machine being thrown twice does not play the same file.
    """
    dur = [0.42, 0.48, 0.54][variant]
    f0 = [232.0, 196.0, 268.0][variant]
    thump_f = [124.0, 108.0, 138.0][variant]
    n = int(dur * SR)
    t = np.arange(n) / SR

    crack = bandpass(strike(n, ms=2.4, hi=8000.0, lo=260.0), 300.0, 7000.0) * 1.6
    body = modal(
        strike(n, ms=1.8, hi=5200.0, lo=140.0),
        steel_modes(f0, count=6),
        [1.0, 0.70, 0.48, 0.32, 0.20, 0.12],
        [0.150, 0.110, 0.080, 0.055, 0.038, 0.024],
    )
    body = saturate(body * 1.4, 1.3)

    f = thump_f * (0.66 + 0.34 * decay(t, 0.045))
    thump = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.085)

    rubber = lowpass(noise(n), 900.0) * decay(t, 0.022) * 1.1

    # The rattle: loose parts, arriving over the next 200 ms at a falling rate.
    rattle = np.zeros(n)
    at = 0.012
    rate = 62.0
    while at < dur * 0.62:
        k = int(0.0016 * SR)
        i = int(at * SR)
        if i + k < n:
            rattle[i:i + k] += noise(k) * np.hanning(k * 2)[:k][::-1] * (0.9 * decay(np.array([at]), 0.11)[0])
        at += 1.0 / rate
        rate *= 0.90
    rattle = modal(rattle, steel_modes(1240.0, count=4), [1.0, 0.6, 0.35, 0.2],
                   [0.014, 0.010, 0.007, 0.005])

    return (1.15 * crack * decay(t, 0.010) + body * decay(t, 0.20)
            + 0.40 * thump + 0.34 * rubber + 0.70 * rattle)


# ---------------------------------------------------------------- wave P (agent F)
#
# The six weapons, the three drives, the overcharge core and the reactive plate all
# played in silence when they landed (docs/wave-p-d1-notes.md, docs/wave-p-d2-notes.md
# section 6). Everything below is built the way the object makes its noise, the same
# rule the rest of this file follows: electricity is a stochastic arc train through a
# resonant channel, a drill is a driven waveguide under friction, a fan is a blade rate
# tone plus the air it throws, a hydraulic leg is a pump and a relief valve.
#
# THE ELECTRIC FAMILY. An arc is not a buzz and it is not noise: it is a very fast
# train of tiny restrikes, each one exciting the ionised channel, whose RATE is what
# the ear calls the pitch and whose irregularity is what stops it sounding like a
# square wave. `_arc_train` is that process, and the prod, the coil and the discharge
# are all three the same generator at three time scales.


def _arc_train(n, rate_hz, ms=0.35, lo=700.0, hi=13000.0, jitter=0.35,
               spread=0.6, wrap=True):
    """A restrike train: short filtered clicks at `rate_hz`, irregular in time and
    in level. Wrapped (and therefore seamless) when `wrap` is true.
    """
    n = int(n)
    out = np.zeros(n)
    step = SR / float(rate_hz)
    count = max(int(round(n / step)), 1)
    k = max(int(SR * ms / 1000.0), 3)
    for i in range(count):
        at = int(round(i * step + RNG.uniform(-jitter, jitter) * step))
        tt = np.arange(k) / SR
        kern = noise(k) * np.exp(-tt / (ms * 0.0007)) * (1.0 + RNG.uniform(-spread, spread))
        if wrap:
            idx = (np.arange(k) + at) % n
        else:
            idx = np.clip(np.arange(k) + at, 0, n - 1)
        out[idx] += kern
    f = circular_filter if wrap else (lambda z, fn: fn(z))
    return f(out, lambda z: bandpass(z, lo, hi))


def arc_crackle_loop():
    """1.5 s seamless. A tesla coil CHARGING: the driver's mains hum under a corona
    that has not broken into an arc yet.

    Three layers. The driver is a 60 Hz series soft clipped, because a switching
    supply under load is anything but a sine. The corona is a fast restrike train at
    about 700 a second, which is above the rate the ear resolves into clicks and is
    therefore heard as a hard fizz. The top is the ozone hiss, almost steady.

    `fx/weapon_fx.gd` pitches and levels this by the coil's charge, so one file
    covers the whole wind-up and the loop never restarts.
    """
    dur = 1.5
    n = int(dur * SR)
    t = np.arange(n) / SR

    driver = np.zeros(n)
    for f, amp in ((60, 1.0), (120, 0.55), (180, 0.30), (300, 0.14), (420, 0.07)):
        driver += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    driver = saturate(driver * 0.7, 1.8) * 0.38

    corona = _arc_train(n, 702.0, ms=0.30, lo=900.0, hi=13500.0, jitter=0.40) * 0.85
    # The channel itself rings: a thin, high, very short resonance on every restrike.
    corona = modal_periodic(corona * 0.5, [3180.0, 5240.0, 7710.0],
                            [1.0, 0.55, 0.3], [0.0016, 0.0011, 0.0008]) + corona
    hiss = 0.30 * periodic_noise(n, 3200.0, 14000.0, tilt=-1.0)
    return (driver + corona + hiss) * lfo(t, [3.0, 11.0], [0.10, 0.06], dur)


def arc_discharge(variant):
    """0.55 s. The coil letting go: a crack, an ionised channel that collapses, and
    the steel it landed on ringing.

    The CRACK is the air: a 0.2 ms strike, because the leading edge is the whole
    event. The channel is a restrike train whose rate falls away as the plasma cools,
    which is the downward "zzip" the ear actually identifies as a spark. Under both
    of them the target plate rings, briefly, because the arc terminated on it.
    """
    dur = 0.55
    n = int(round(dur * SR))
    t = np.arange(n) / SR

    crack = strike(n, ms=0.22, hi=15000.0, lo=900.0) * 1.9
    # The channel: the rate falls by two thirds over the first 40 ms.
    fall = np.exp(-t / 0.040)
    chan = _arc_train(n, 1400.0 - 280.0 * variant, ms=0.22, lo=800.0, hi=14000.0,
                      jitter=0.45, wrap=False)
    chan *= (0.35 + 0.65 * fall)
    plate = modal(strike(n, 0.5, 11000.0),
                  steel_modes(870.0 + 140.0 * variant, count=6),
                  [1.0, 0.62, 0.40, 0.26, 0.16, 0.09],
                  [0.085, 0.060, 0.042, 0.030, 0.020, 0.014]) * 1.5
    # The bang has a low end: the air in the gap expanding.
    thump = np.sin(2.0 * np.pi * np.cumsum(96.0 * (0.6 + 0.4 * decay(t, 0.02))) / SR) \
        * decay(t, 0.055)
    return crack * decay(t, 0.014) + 2.6 * chan + plate * decay(t, 0.28) + 0.85 * thump


def prod_zap(variant):
    """0.32 s. A welded contact prod biting: a stun gun, not a lightning bolt.

    The whole character is the RATE: a prod arcs at a few tens of restrikes a second,
    slow enough that the ear hears the individual snaps, which is why a stun gun
    rattles where a tesla coil fizzes. On top of it the two prongs ring (they are
    small steel rods, so the modes are high and die in milliseconds) and the plate it
    is held against buzzes with them.
    """
    dur = 0.32
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    rate = 88.0 + 14.0 * variant
    snaps = _arc_train(n, rate, ms=0.45, lo=600.0, hi=11000.0, jitter=0.28,
                       spread=0.75, wrap=False)
    prongs = modal(snaps * 0.35, steel_modes(2260.0 + 180.0 * variant, count=4),
                   [1.0, 0.55, 0.3, 0.16], [0.0085, 0.0060, 0.0040, 0.0028])
    buzz = np.sin(2.0 * np.pi * rate * 2.0 * t) * 0.30 * decay(t, 0.14)
    return (2.4 * snaps + 1.3 * prongs + buzz) * decay(t, 0.17)


def drill_grind_loop():
    """1.2 s seamless. A helical lance boring into a plate.

    It is the bandsaw's physics at a different scale: the lance is a long steel body
    under continuous friction, so it is a driven waveguide, but it is ONE shaft
    rather than a thin blade, so it is lower, duller and rougher. The flutes give the
    grind its rate (six flutes at three revolutions a second is 18 Hz, slow enough to
    be a chatter rather than a tone), and the motor bogs underneath.
    """
    dur = 1.20
    n = int(dur * SR)
    fade_n = int(0.08 * SR)
    m = n + fade_n
    t = np.arange(m) / SR

    friction = bandpass(noise(m), 400.0, 7000.0) * (0.55 + 0.45 * np.abs(noise(m)))
    shaft = waveguide(friction * 0.40, 318.0, loop_gain=0.978, brightness=0.55)
    shaft += 0.45 * waveguide(friction * 0.22, 763.0, loop_gain=0.955, brightness=0.70)
    shaft = saturate(shaft * 0.35, 1.5) * 1.7

    flute = 0.5 + 0.5 * np.sin(2.0 * np.pi * 18.0 * t)
    swarf = bandpass(noise(m), 900.0, 6500.0) * (0.30 + 0.70 * flute) * 0.60
    bite = bandpass(noise(m), 70.0, 320.0) * 0.26        # the cut loading the motor
    motor = 0.20 * saturate(
        np.sin(2.0 * np.pi * 96.0 * t) + 0.55 * np.sin(2.0 * np.pi * 192.0 * t), 1.7)
    wobble = 1.0 + 0.10 * np.sin(2.0 * np.pi * 5.0 * t) + 0.06 * np.sin(2.0 * np.pi * 2.0 * t)
    return crossfade_loop((shaft + swarf + bite + motor) * wobble, n, fade_ms=80.0)


def twin_saw_loop():
    """1.2 s seamless. ONE disc of the twin saw, played twice an octave apart.

    Two discs on one arbor never run at the same speed (different loads, different
    teeth in the work), and two copies of one file at the same pitch is a phase
    problem rather than a second blade. `fx/weapon_fx.gd` starts two voices from this
    file at pitch p and 2p, so the pair reads as two bodies with one drive.

    Written deliberately LOW and tonal, because the upper voice is an octave up: a
    file that is already bright ends as a whistle.
    """
    dur = 1.20
    n = int(dur * SR)
    fade_n = int(0.08 * SR)
    m = n + fade_n
    t = np.arange(m) / SR

    friction = bandpass(noise(m), 800.0, 10000.0) * (0.6 + 0.4 * np.abs(noise(m)))
    blade = waveguide(friction * 0.32, 524.0, loop_gain=0.986, brightness=0.78)
    blade += 0.55 * waveguide(friction * 0.18, 1261.0, loop_gain=0.966, brightness=0.88)
    blade = saturate(blade * 0.33, 1.25) * 1.95

    tooth = 0.5 + 0.5 * np.sin(2.0 * np.pi * 112.0 * t)
    grind = bandpass(noise(m), 420.0, 5200.0) * (0.40 + 0.60 * tooth) * 0.50
    arbor = 0.14 * saturate(np.sin(2.0 * np.pi * 131.0 * t)
                            + 0.5 * np.sin(2.0 * np.pi * 262.0 * t), 1.6)
    wobble = 1.0 + 0.07 * np.sin(2.0 * np.pi * 7.5 * t) + 0.04 * np.sin(2.0 * np.pi * 3.0 * t)
    return crossfade_loop((blade + grind + arbor) * wobble, n, fade_ms=80.0)


def napalm_launch():
    """0.45 s. A short mortar tube throwing a charge.

    A mortar is a pressure event in a pipe, so it is a low thump whose pitch falls as
    the gas leaves, the tube's own ring on top of it, and a breathy exhaust that
    outlasts both. There is no crack: the charge is thrown, not fired.
    """
    dur = 0.45
    n = int(round(dur * SR))
    t = np.arange(n) / SR

    f = 118.0 * (0.55 + 0.45 * decay(t, 0.030))
    thump = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.070) * 1.6
    tube = modal(strike(n, 0.8, 7000.0, 300.0), steel_modes(430.0, count=5),
                 [1.0, 0.55, 0.32, 0.18, 0.10],
                 [0.055, 0.038, 0.026, 0.018, 0.012]) * 0.85
    gas = bandpass(noise(n), 260.0, 5200.0) * decay(t, 0.13) * 0.75
    gas += bandpass(noise(n), 40.0, 200.0) * decay(t, 0.09) * 0.45
    return thump + tube * decay(t, 0.16) + gas


def fire_patch_loop():
    """2 s seamless. Fuel burning on the arena floor, which is not a burner.

    `flame_loop` is a jet: it has a nozzle resonance and a steady hiss because gas is
    being forced through a hole. A puddle has neither. What it has instead is a slow,
    heavy roll (the flame front wandering over the pool, a few hertz), very little
    top, and the occasional pop as something in the fuel flashes off. Every layer is
    frequency domain noise, so it is exactly periodic and needs no crossfade.
    """
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR

    def env(lo, hi, depth):
        e = periodic_noise(n, lo, hi, tilt=-6.0)
        e = e / (np.max(np.abs(e)) + 1e-9)
        return 1.0 + depth * e

    roll = periodic_noise(n, 35.0, 220.0, tilt=-2.0) * env(0.5, 4.0, 0.95) * 0.95
    body = periodic_noise(n, 220.0, 1400.0, tilt=-4.0) * env(1.5, 11.0, 0.70) * 0.70
    lick = periodic_noise(n, 1400.0, 7000.0, tilt=-6.0) * env(4.0, 26.0, 0.55) * 0.24
    # Pops: a few a second, wrapped, each one a tiny low thump rather than a click.
    pops = impulse_train(n, 6.0, ms=3.0, hi=1800.0, lo=90.0, jitter=0.45,
                         gain_spread=0.8) * 0.55
    return saturate(roll + body + lick + pops, 1.05)


def vortex_spin_loop():
    """1 s seamless. The vortex ring: a full body spinner whose teeth are scoops.

    The difference from `spin_up_loop` is the air. A flat ring cuts through it; a
    raked, scooped ring MOVES it, so the layer that carries the sound is a broad roar
    gated hard at the blade passing rate, with the motor's harmonic stack under it
    rather than over it. Written low (150 Hz) because readiness pitches it up to 2.1.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h, amp in ((1, 0.70), (2, 1.0), (3, 0.55), (4, 0.33), (6, 0.16), (8, 0.08)):
        x += amp * np.sin(2.0 * np.pi * (150 * h) * t + RNG.uniform(0, 2 * np.pi))
    x = saturate(x * 0.45, 1.3) * 0.80

    scoop = burst_gate(t, 24.0, dur, duty=0.55, depth=0.85, shape=1.6)
    roar = 0.95 * periodic_noise(n, 120.0, 7200.0, tilt=-3.0) * (0.30 + 0.70 * scoop)
    thrash = 0.30 * periodic_noise(n, 30.0, 160.0, tilt=-4.0) * (0.5 + 0.5 * scoop)
    bearing = 0.09 * periodic_noise(n, 2600.0, 9500.0, tilt=-1.0)
    return (x + roar + thrash + bearing) * lfo(t, [4.0], [0.06], dur)


def vortex_throw():
    """0.6 s. The bite that lifts: a hard steel strike and the air going UP with it.

    The whoop is an upward sweep, which is the one place in this file a sweep is
    honest: the machine that was hit is accelerating away from the ring, so the air
    it is dragging really does rise in pitch.
    """
    dur = 0.60
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    bite = modal(strike(n, 0.35, 12000.0), steel_modes(388.0, count=7),
                 [1.0, 0.70, 0.46, 0.30, 0.20, 0.12, 0.07],
                 [0.130, 0.092, 0.064, 0.045, 0.030, 0.021, 0.014]) * 1.2
    rise = 210.0 * (1.0 + 2.4 * np.clip(t / 0.22, 0.0, 1.0))
    whoop = bandpass(noise(n), 300.0, 6000.0) * 0.55
    whoop *= np.clip(t / 0.05, 0.0, 1.0) * decay(t, 0.15)
    whoop += 0.30 * np.sin(2.0 * np.pi * np.cumsum(rise) / SR) * decay(t, 0.14)
    f = 74.0 * (0.7 + 0.3 * decay(t, 0.03))
    thump = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.080) * 0.9
    return bite * decay(t, 0.30) + whoop + thump


def footfall(variant):
    """0.34 s. One hydraulic leg planting on the boards.

    Three things in order, all of them the machine's: the ram (a short hiss as the
    fluid moves), the foot (a damped low thud, because a rubber shod foot on a steel
    deck is not a clang), and the linkage taking up its slack a few milliseconds
    later, which is the small steel clack that makes it read as a MACHINE walking.
    """
    dur = 0.34
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    ram = bandpass(noise(n), 700.0, 6000.0) * decay(t, 0.030) * 0.55
    f = (88.0 + 9.0 * variant) * (0.65 + 0.35 * decay(t, 0.020))
    thud = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.055) * 1.5
    deck = modal(strike(n, 1.2, 3200.0, 120.0), steel_modes(196.0, count=4),
                 [1.0, 0.5, 0.28, 0.15], [0.048, 0.033, 0.022, 0.015]) * 0.55
    clack_at = int(SR * (0.018 + 0.004 * variant))
    clack = np.zeros(n)
    tail = n - clack_at
    clack[clack_at:] = modal(strike(tail, 0.3, 9000.0),
                             steel_modes(1560.0 + 90.0 * variant, count=4),
                             [1.0, 0.55, 0.3, 0.16],
                             [0.012, 0.008, 0.005, 0.004]) * 0.45
    return ram + thud + deck * decay(t, 0.16) + clack


def hover_fan_loop():
    """1 s seamless. A lift impeller.

    A fan's sound is its BLADE PASSING RATE and the air it throws, in that order. The
    tone is at the blade rate with a harmonic stack, the air is a broad roar gated by
    the same rate so it pulses with the blades, and the bearing sits on top. Written
    at 132 Hz, low for a fan, because MachineAudio pitches it up to 2.0 at top speed
    and a hover that screams at a standstill is a toy.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    blade = np.zeros(n)
    for h, amp in ((1, 1.0), (2, 0.70), (3, 0.42), (4, 0.24), (5, 0.14), (7, 0.07)):
        blade += amp * np.sin(2.0 * np.pi * (132 * h) * t + RNG.uniform(0, 2 * np.pi))
    blade = saturate(blade * 0.55, 1.4) * 0.70
    gate = burst_gate(t, 132.0, dur, duty=0.6, depth=0.5, shape=2.2)
    air = 0.85 * periodic_noise(n, 300.0, 9000.0, tilt=-2.5) * (0.45 + 0.55 * gate)
    inlet = 0.35 * periodic_noise(n, 60.0, 300.0, tilt=-3.0)
    bearing = 0.10 * periodic_noise(n, 3000.0, 11000.0, tilt=-1.0)
    return (blade + air + inlet + bearing) * lfo(t, [6.0, 2.0], [0.05, 0.03], dur)


def hover_skirt_loop():
    """1 s seamless. Air escaping under the skirt: the hover's contact with the floor.

    It is the roll slot in `MachineAudio.DRIVES`, and it is the one drive in the game
    whose contact sound has no impulses in it at all. A cushion leaking is broadband
    hiss with a pressure wobble; when the skirt touches down it flutters, which is
    the slow gate.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    hiss = periodic_noise(n, 400.0, 11000.0, tilt=-2.0) * 0.85
    flutter = burst_gate(t, 17.0, dur, duty=0.7, depth=0.35, shape=1.4)
    press = 0.55 * periodic_noise(n, 45.0, 260.0, tilt=-3.5)
    return (hiss * (0.55 + 0.45 * flutter) + press) * lfo(t, [3.0, 9.0], [0.10, 0.06], dur)


def leg_servo_loop():
    """1 s seamless. The walker's hydraulics between footfalls.

    A hydraulic pack is a positive displacement pump (a pulse per piston, so a train
    at the piston rate), a relief valve that whines, and fluid moving in the lines.
    Slow and heavy: this machine's whole character is that it is not in a hurry.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    pump = impulse_train(n, 27.0, ms=2.2, hi=1500.0, lo=55.0, jitter=0.05,
                         gain_spread=0.25) * 0.95
    pump = modal_periodic(pump * 0.5, [118.0, 236.0, 402.0], [1.0, 0.5, 0.25],
                          [0.020, 0.014, 0.009]) + pump
    whine = np.zeros(n)
    for f, amp in ((324, 0.30), (648, 0.13), (972, 0.05)):
        whine += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    whine *= lfo(t, [9.0], [0.30], dur)
    fluid = 0.30 * periodic_noise(n, 500.0, 6000.0, tilt=-3.0)
    return (pump + whine + fluid) * lfo(t, [2.0, 5.0], [0.07, 0.04], dur)


def adaptive_track_loop():
    """1 s seamless. A segmented belt, which is not the same object as a track.

    `track_clatter_loop` is a link belt: big plates slapping the deck at 26 a second.
    An adaptive track is short segments on a compliant carrier, so the link rate is
    more than twice as high and every slap is smaller, softer and more damped. The
    result reads as a finer, busier belt, which is exactly what the part is: track
    grip with a 4WD's steering and nothing to tear off.
    """
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    links = impulse_train(n, 58.0, ms=0.9, hi=6500.0, lo=220.0, jitter=0.10,
                          gain_spread=0.45) * 0.90
    # Each segment is small, so its modes are high and die in a few milliseconds.
    plate = modal_periodic(links * 0.45, [880.0, 1410.0, 2260.0, 3380.0],
                           [1.0, 0.55, 0.30, 0.16],
                           [0.0110, 0.0080, 0.0055, 0.0038])
    rollers = impulse_train(n, 116.0, ms=0.5, hi=9000.0, lo=900.0, jitter=0.18,
                            gain_spread=0.5) * 0.30
    carrier = 0.42 * periodic_noise(n, 55.0, 380.0, tilt=-3.0)
    return (links * 0.7 + plate + rollers + carrier) * lfo(t, [4.0, 7.0], [0.06, 0.04], dur)


def cook_warning():
    """0.30 s. The overcharge core running hot.

    Not a beep. A steel casing that is expanding faster than it can spread the heat
    TICKS, sharply, as the strain releases, and that is a struck plate with almost no
    decay. Two ticks a few milliseconds apart, because the release is never one
    event, over a thin sizzle. `fx/weapon_fx.gd` plays it faster and higher as the
    cook climbs, so the count closing in is the tick rate, not the sound.
    """
    dur = 0.20
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    tick = modal(strike(n, 0.25, 14000.0, 1200.0), steel_modes(2840.0, count=5),
                 [1.0, 0.60, 0.36, 0.20, 0.11],
                 [0.0230, 0.0160, 0.0110, 0.0075, 0.0050]) * 1.4
    second_at = int(SR * 0.021)
    tail = n - second_at
    second = np.zeros(n)
    second[second_at:] = modal(strike(tail, 0.2, 14000.0, 1200.0),
                               steel_modes(3420.0, count=4),
                               [1.0, 0.55, 0.30, 0.16],
                               [0.0090, 0.0062, 0.0042, 0.0028]) * 0.75
    sizzle = bandpass(noise(n), 2500.0, 12000.0) * decay(t, 0.075) * 0.50
    return tick * decay(t, 0.13) + second + sizzle


def reactive_clang(variant):
    """0.75 s. A reactive plate firing its charge into whatever hit it.

    Three events inside eight milliseconds: the charge (a hard broadband crack with a
    low end, because it is a small explosion), the plate itself thrown against its
    mounts (the big ring, and it is the loudest thing here), and the attacker taking
    the shove. It is deliberately close to `panel_off` in family and much shorter in
    decay: a plate that fires is not a plate that came off.
    """
    dur = 0.75
    n = int(round(dur * SR))
    t = np.arange(n) / SR
    crack = strike(n, ms=0.30, hi=13000.0, lo=500.0) * 4.2 * decay(t, 0.010)
    f = 104.0 * (0.55 + 0.45 * decay(t, 0.018))
    blast = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.048) * 1.5
    plate = modal(strike(n, 0.6, 9000.0, 260.0),
                  steel_modes(268.0 + 34.0 * variant, count=7),
                  [1.0, 0.72, 0.48, 0.32, 0.20, 0.12, 0.07],
                  [0.150, 0.108, 0.076, 0.052, 0.036, 0.024, 0.016]) * 1.35
    mounts_at = int(SR * (0.007 + 0.002 * variant))
    tail = n - mounts_at
    mounts = np.zeros(n)
    mounts[mounts_at:] = modal(strike(tail, 0.3, 11000.0),
                               steel_modes(1180.0 + 120.0 * variant, count=4),
                               [1.0, 0.55, 0.30, 0.16],
                               [0.020, 0.014, 0.009, 0.006]) * 0.65
    return crack + blast + plate * decay(t, 0.26) + mounts


# ---------------------------------------------------------------- the crowd


def _crowd_bed(n, dur, claps_per_s, tilt=-2.0):
    """One side of the arena bed: murmur, hall air and a clap field.

    The murmur is unchanged in kind from agent AU's (band limited noise whose only
    movement is slow amplitude modulation, so it is structurally incapable of
    containing words, docs/audio-notes.md §3) and changed in PLACEMENT: the old bed
    put 97 % of its energy between 200 Hz and 2 kHz with 2.9 % above 2 kHz, which is
    a crowd heard through a wall. A real crowd on a phone speaker is mostly hands.
    """
    t = np.arange(n) / SR
    murmur = periodic_noise(n, 240.0, 2600.0, tilt=tilt)
    murmur *= lfo(t, [0.25, 0.625, 1.375, 2.5], [0.16, 0.11, 0.07, 0.04], dur)
    air = 0.30 * periodic_noise(n, 2600.0, 9000.0, tilt=-3.0)
    air *= lfo(t, [0.375, 1.125], [0.12, 0.08], dur)
    swell = lfo(t, [0.125, 0.25], [0.22, 0.12], dur) - 1.0
    density = claps_per_s * (1.0 + 0.55 * swell)
    claps = clap_field(n, density, ms=2.4, lo=1100.0, hi=8000.0)
    claps /= np.max(np.abs(claps)) + 1e-9
    return murmur * (1.0 + 0.5 * swell) + air + 0.55 * claps


def crowd_ambience_loop():
    """8 s seamless STEREO arena bed. REBUILT in wave F, and why.

    The owner played wave G on his iPhone and could not hear the crowd. Two separate
    causes, both measured (docs/wave-f-f2-notes.md):

    1. LEVEL. The bed's mono-sum RMS was -21 dBFS, on the Ambience bus at -14 dB with
       a -6 dB trim on top: -41 dBFS of crowd against a -6 dBFS impact. Fixed in
       AudioMix.LEVELS and the bus layout, not here.
    2. PLACEMENT. 96.9 % of its energy sat between 200 Hz and 2 kHz and 2.9 % above
       2 kHz. That is a correct model of a distant murmur and the wrong model of a
       crowd on a phone speaker, where the useful band starts around 700 Hz. A real
       arena crowd's audible signature on a small speaker is CLAPS, and there were
       none in it.

    So the murmur stays (and stays word-free: band limited noise, amplitude
    modulation only, no formant motion, nothing above a 4 Hz envelope) and a clap
    field goes over it, plus hall air up to 9 kHz. Claps are broadband transients,
    which is the furthest thing there is from speech-shaped content.

    Still exactly periodic: frequency-domain noise, modulators with whole numbers of
    cycles per loop, clap kernels placed with a wrap, and a CIRCULAR hall.
    """
    dur = 8.0
    n = int(dur * SR)

    def side():
        body = _crowd_bed(n, dur, claps_per_s=9.0)
        pa = np.zeros(n)
        t = np.arange(n) / SR
        for f, amp in ((50, 1.0), (100, 0.45), (150, 0.25), (250, 0.08)):
            pa += amp * np.sin(2.0 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
        pa = pa * 0.008 + 0.022 * periodic_noise(n, 800.0, 14000.0, tilt=-1.0)
        wet = circular_reverb(body, decay_s=0.85, pre_ms=14.0, hf_damp=4800.0)
        wet /= np.max(np.abs(wet)) + 1e-9
        return 0.62 * body + 0.62 * wet + pa

    left = side()
    right = side()
    lo_l = lowpass(np.tile(left, 3), 220.0)[n:2 * n]
    lo_r = lowpass(np.tile(right, 3), 220.0)[n:2 * n]
    mid = 0.5 * (lo_l + lo_r)
    left = left - lo_l + mid
    right = right - lo_r + mid
    out = np.stack([left, right], axis=1)
    # A bed is not a transient: soft clip the last few percent so the file can be
    # normalised to -3 dBFS peak without the RMS being set by two stray claps.
    return saturate(out * 1.25, 1.1)


def crowd_swell(variant):
    """2.2 / 2.6 s. The crowd reacting to one thing: a big hit, or a machine going
    over. Not a cheer track and not a sample of people: the same murmur bed swelling
    hard, with the clap density rising underneath it, in the same hall.

    The whole point of this file is that the arena stops being a loop. A crowd that
    never reacts is a recording; a crowd that lifts a second after a bar goes through
    an armour plate is an audience.
    """
    dur = [2.2, 2.6][variant]
    n = int(dur * SR)
    t = np.arange(n) / SR

    # Rise fast, hold, fall slowly: people react in about 150 ms and settle in two
    # seconds. The asymmetry is the whole envelope.
    rise = [0.16, 0.22][variant]
    env = np.clip(t / rise, 0.0, 1.0) * (0.30 + 0.70 * decay(np.maximum(t - rise, 0.0),
                                                             [0.55, 0.70][variant]))

    voices = bandpass(noise(n), 320.0, 3200.0) * env
    voices = voices * (1.0 + 0.25 * _slow(n, 6.0))
    air = 0.35 * bandpass(noise(n), 3000.0, 9500.0) * env ** 1.6
    claps = clap_field(n, 150.0 * env ** 1.4, ms=2.2, lo=1200.0, hi=8500.0, wrap=False)
    claps /= np.max(np.abs(claps)) + 1e-9

    dry = 0.85 * voices + air + 0.75 * claps * env
    wet = room(dry, decay_s=0.70, pre_ms=12.0, hf_damp=5200.0)[:n]
    wet /= np.max(np.abs(wet)) + 1e-9
    return saturate((0.60 * dry + 0.70 * wet) * 1.2, 1.15)


def crowd_roar():
    """3.4 s. The big one: the knockout count and the endgame horn.

    Same construction as `crowd_swell`, longer and denser, and with the low wall of
    massed voices a full house has and a reaction does not. It is the only crowd file
    allowed to be a moment in its own right.
    """
    dur = 3.4
    n = int(dur * SR)
    t = np.arange(n) / SR

    env = np.clip(t / 0.34, 0.0, 1.0) * (0.34 + 0.66 * decay(np.maximum(t - 0.34, 0.0), 1.15))
    voices = bandpass(noise(n), 260.0, 3600.0) * env
    voices = voices * (1.0 + 0.30 * _slow(n, 5.0))
    wall = 0.45 * bandpass(noise(n), 180.0, 900.0) * env ** 0.8
    air = 0.40 * bandpass(noise(n), 3000.0, 10000.0) * env ** 1.5
    claps = clap_field(n, 230.0 * env ** 1.2, ms=2.4, lo=1100.0, hi=8500.0, wrap=False)
    claps /= np.max(np.abs(claps)) + 1e-9

    dry = 0.85 * voices + wall + air + 0.85 * claps * env
    wet = room(dry, decay_s=0.95, pre_ms=16.0, hf_damp=4800.0)[:n]
    wet /= np.max(np.abs(wet)) + 1e-9
    return saturate((0.55 * dry + 0.75 * wet) * 1.25, 1.2)


def crowd_boo():
    """3.0 s. Wave D (docs/wave-d-marshal-notes.md): the crowd disagreeing with a close
    judges' decision. The same hall as the swell and the roar, but VOICES rather than
    hands: forty-odd people holding one low "oo" and letting it sag, plus two whistles.

    No words: a held vowel is not speech (one static formant pair, /u/ at ~320 and
    ~850 Hz, no formant motion), no chant, no single voice on top. Every voice is a
    buzzy harmonic source with its own pitch, onset, vibrato and a two-semitone fall,
    which is what makes a boo a boo and not an organ chord.
    """
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.clip(t / 0.28, 0.0, 1.0) * np.clip((dur - 0.05 - t) / 1.0, 0.0, 1.0) ** 1.3

    voices = np.zeros(n)
    for k in range(44):
        f0 = RNG.uniform(88.0, 175.0) if k % 3 else RNG.uniform(170.0, 250.0)
        onset = RNG.uniform(0.0, 0.3)
        fall = 1.0 - 0.11 * np.clip((t - onset) / 2.3, 0.0, 1.0)
        vib = 1.0 + 0.013 * np.sin(2.0 * np.pi * RNG.uniform(4.2, 6.2) * t + RNG.uniform(0, 2 * np.pi))
        phase = 2.0 * np.pi * np.cumsum(f0 * fall * vib) / SR
        src = np.zeros(n)
        for h in range(1, 11):
            src += np.sin(h * phase + RNG.uniform(0, 2 * np.pi)) / h
        venv = np.clip((t - onset) / 0.22, 0.0, 1.0)
        venv = venv * (1.0 + 0.18 * np.sin(2.0 * np.pi * RNG.uniform(0.4, 1.4) * t + RNG.uniform(0, 2 * np.pi)))
        voices += src * venv * RNG.uniform(0.55, 1.0)
    voices /= np.max(np.abs(voices)) + 1e-9
    oo = bandpass(voices, 250.0, 430.0) + 0.45 * bandpass(voices, 700.0, 1000.0) \
        + 0.08 * bandpass(voices, 2200.0, 2900.0)
    oo /= np.max(np.abs(oo)) + 1e-9
    breath = 0.10 * bandpass(noise(n), 300.0, 1500.0)

    whistles = np.zeros(n)
    for start, top in ((0.55, 3100.0), (1.45, 2800.0)):
        w_t = t - start
        live = (w_t >= 0.0) & (w_t <= 0.75)
        k = np.clip(w_t / 0.75, 0.0, 1.0)
        f = 2300.0 + (top - 2300.0) * np.sin(np.pi * k) ** 0.6
        ph = 2.0 * np.pi * np.cumsum(np.where(live, f, 0.0)) / SR
        w_env = np.where(live, np.sin(np.pi * k) ** 0.5, 0.0)
        whistles += 0.16 * np.sin(ph) * w_env

    dry = (oo + breath) * env + whistles
    wet = room(dry, decay_s=0.95, pre_ms=14.0, hf_damp=4200.0)[:n]
    wet /= np.max(np.abs(wet)) + 1e-9
    return saturate((0.60 * dry + 0.70 * wet) * 1.2, 1.15)


# ================================================================ main


def build_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Roboteer sounds -> %s\n" % OUT_DIR)

    # `build` re-seeds RNG per file name (see STREAM_SEED), so the order of this list
    # is presentation only: moving, adding or changing a sound cannot alter any other.

    print("-- feedback ------------------------------------------------")
    build("bolt_collect.wav", bolt_collect, in_ms=0.2, out_ms=4.0)
    for i in range(3):
        build("impact_light_%d.wav" % (i + 1), impact_light, i, in_ms=0.2, out_ms=6.0)
    for i in range(3):
        build("impact_heavy_%d.wav" % (i + 1), impact_heavy, i, in_ms=0.2, out_ms=14.0)

    print("\n-- weapons -------------------------------------------------")
    build("flipper_fire.wav", flipper_fire, in_ms=0.5, out_ms=14.0)
    build("axe_swing.wav", axe_swing, in_ms=3.0, out_ms=14.0)
    build("axe_hit.wav", axe_hit, in_ms=0.2, out_ms=16.0)
    build("ram_hit.wav", ram_hit, in_ms=0.2, out_ms=16.0)
    build("crusher_clamp.wav", crusher_clamp, in_ms=3.0, out_ms=20.0)

    print("\n-- parts coming off ----------------------------------------")
    build("wheel_off.wav", wheel_off, in_ms=0.3, out_ms=16.0)
    build("panel_off.wav", panel_off, in_ms=0.3, out_ms=16.0)

    print("\n-- loops ---------------------------------------------------")
    build("motor_loop.wav", motor_loop, loop=True)
    build("spin_up_loop.wav", spin_up_loop, loop=True)
    build("saw_cut_loop.wav", saw_cut_loop, loop=True)
    build("flame_loop.wav", flame_loop, loop=True)
    build("grinder_loop.wav", grinder_loop, loop=True)
    build("disc_spin_loop.wav", disc_spin_loop, loop=True)

    print("\n-- arena hazards -------------------------------------------")
    build("spikes.wav", spikes, in_ms=1.0, out_ms=14.0)
    build("pit_open.wav", pit_open, in_ms=2.0, out_ms=20.0)
    build("flame_jet.wav", flame_jet, in_ms=0.3, out_ms=20.0)
    build("ram_crush.wav", ram_crush, in_ms=0.2, out_ms=24.0)
    # wave A: the shared warning language's wind-ups, 1.25 s before each hazard acts.
    build("warn_spikes.wav", warn_spikes, in_ms=1.0, out_ms=12.0)
    build("warn_flame.wav", warn_flame, in_ms=1.0, out_ms=12.0)
    build("warn_ram.wav", warn_ram, in_ms=2.0, out_ms=12.0)
    build("warn_pit.wav", warn_pit, in_ms=1.0, out_ms=12.0)

    print("\n-- fight and UI --------------------------------------------")
    build("countdown_tick.wav", countdown_tick, in_ms=0.3, out_ms=6.0)
    build("ko_tick.wav", ko_tick, in_ms=0.3, out_ms=8.0)
    build("bell.wav", bell, in_ms=0.3, out_ms=60.0)

    print("\n-- endgame (brief v4 §2) -----------------------------------")
    build("endgame_horn.wav", endgame_horn, in_ms=0.2, out_ms=24.0)
    build("endgame_drone_loop.wav", endgame_drone_loop, loop=True)

    # Wave F (F2). The movement layer: every machine on the floor, driven from its own
    # drive state each frame by Arena/fx/machine_audio.gd.
    print("\n-- movement (wave F) ---------------------------------------")
    build("drive_whine_loop.wav", drive_whine_loop, loop=True)
    build("roll_wheel_loop.wav", roll_wheel_loop, loop=True)
    build("track_clatter_loop.wav", track_clatter_loop, loop=True)
    build("roll_omni_loop.wav", roll_omni_loop, loop=True)
    build("skid_loop.wav", skid_loop, loop=True)
    build("scrape_loop.wav", scrape_loop, loop=True)
    for i in range(3):
        build("chassis_thud_%d.wav" % (i + 1), chassis_thud, i, in_ms=0.2, out_ms=18.0)

    # Wave P (F). The six weapons, the three drives, the overcharge core and the
    # reactive plate: everything that landed in wave P and played in silence.
    print("\n-- wave P weapons ------------------------------------------")
    build("arc_crackle_loop.wav", arc_crackle_loop, loop=True)
    for i in range(2):
        build("arc_discharge_%d.wav" % (i + 1), arc_discharge, i, in_ms=0.1, out_ms=18.0)
    for i in range(2):
        build("prod_zap_%d.wav" % (i + 1), prod_zap, i, in_ms=0.1, out_ms=10.0)
    build("drill_grind_loop.wav", drill_grind_loop, loop=True)
    build("twin_saw_loop.wav", twin_saw_loop, loop=True)
    build("napalm_launch.wav", napalm_launch, in_ms=0.2, out_ms=16.0)
    build("fire_patch_loop.wav", fire_patch_loop, loop=True)
    build("vortex_spin_loop.wav", vortex_spin_loop, loop=True)
    build("vortex_throw.wav", vortex_throw, in_ms=0.2, out_ms=20.0)

    print("\n-- wave P mobility and utility -----------------------------")
    for i in range(2):
        build("footfall_%d.wav" % (i + 1), footfall, i, in_ms=0.2, out_ms=12.0)
    build("hover_fan_loop.wav", hover_fan_loop, loop=True)
    build("hover_skirt_loop.wav", hover_skirt_loop, loop=True)
    build("leg_servo_loop.wav", leg_servo_loop, loop=True)
    build("adaptive_track_loop.wav", adaptive_track_loop, loop=True)
    build("cook_warning.wav", cook_warning, in_ms=0.1, out_ms=10.0)
    for i in range(2):
        build("reactive_clang_%d.wav" % (i + 1), reactive_clang, i, in_ms=0.1, out_ms=22.0)

    print("\n-- the crowd (wave F) --------------------------------------")
    build("crowd_ambience_loop.wav", crowd_ambience_loop, loop=True)
    for i in range(2):
        build("crowd_swell_%d.wav" % (i + 1), crowd_swell, i, in_ms=1.0, out_ms=60.0)
    build("crowd_roar.wav", crowd_roar, in_ms=2.0, out_ms=90.0)

    print("\n-- the crowd's verdict (wave D) ----------------------------")
    build("crowd_boo.wav", crowd_boo, in_ms=2.0, out_ms=90.0)

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
    # PCM, not QOA, beyond the loops. `bolt_collect` because it is 45 ms and is pitched
    # up two octaves, which is exactly where a lossy codec's high band shows; the three
    # crowd cues (wave F) because they are mostly CLAPS, and a transient-dense broadband
    # file is the other case QOA smears. It also means `audio_test.gd` can measure their
    # loudness off the imported bytes, which it cannot do for a QOA stream.
    pcm_only = LOOPS + ["bolt_collect.wav", "crowd_swell_1.wav", "crowd_swell_2.wav",
                        "crowd_roar.wav", "crowd_boo.wav",
                        # Wave P (F). The electric family is almost entirely restrike
                        # transients, which is the other case QOA smears, and the cook
                        # tick is 30 ms of nothing but transient. PCM also lets
                        # audio_test measure their loudness off the imported bytes.
                        "arc_discharge_1.wav", "arc_discharge_2.wav",
                        "prod_zap_1.wav", "prod_zap_2.wav",
                        "cook_warning.wav",
                        "reactive_clang_1.wav", "reactive_clang_2.wav",
                        "napalm_launch.wav", "vortex_throw.wav",
                        "footfall_1.wav", "footfall_2.wav"]
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
    if "--only" in sys.argv:
        # One file, by name, leaving every other file's bytes alone (wave D added this so
        # a new sound does not rewrite 60 committed files on a newer numpy).
        wanted = sys.argv[sys.argv.index("--only") + 1]
        table = {"crowd_boo.wav": (crowd_boo, {"in_ms": 2.0, "out_ms": 90.0})}
        fn, kw = table[wanted]
        os.makedirs(OUT_DIR, exist_ok=True)
        build(wanted, fn, **kw)
        return 0
    build_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
