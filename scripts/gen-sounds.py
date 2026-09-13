#!/usr/bin/env python3
"""Generate the Stage 3 placeholder fight sounds into Arena/audio/.

These are synthesised placeholders for feel testing only (docs/stage3-spec.md §11).
Recorded or sampled sounds replace them later; nothing here is final audio.

Output: 44.1 kHz, 16-bit, mono WAV. Every file is normalised to -3 dBFS peak and
given short fades so nothing clicks. motor_loop.wav is the one exception: it is
built entirely from components whose period divides its length, so it is sample
accurate seamless and must NOT be faded.

    python3 scripts/gen-sounds.py
"""

import os

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
PEAK_DBFS = -3.0
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "Arena", "audio")

# One seeded generator so re-running the script reproduces byte identical files.
RNG = np.random.default_rng(20260913)


# ---------------------------------------------------------------- helpers


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


def partials(t, freqs, amps, taus):
    """Sum of decaying sines. Inharmonic freq sets read as metal."""
    out = np.zeros_like(t)
    for f, a, tau in zip(freqs, amps, taus):
        phase = RNG.uniform(0.0, 2.0 * np.pi)
        out += a * np.sin(2.0 * np.pi * f * t + phase) * decay(t, tau)
    return out


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


def write(name, x, do_fade=True, in_ms=2.0, out_ms=6.0):
    x = np.asarray(x, dtype=np.float64)
    if do_fade:
        x = fade(x, in_ms, out_ms)
    x = normalise(x)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    wavfile.write(path, SR, pcm)
    print("%-20s %5d samples  %6.3f s" % (name, len(pcm), len(pcm) / SR))
    return path


# ---------------------------------------------------------------- sounds


def bolt_collect():
    """40 ms bright metallic tick. FM around 1.8 kHz with a very fast decay."""
    t = t_axis(0.040)
    env = decay(t, 0.0075)
    carrier = 1800.0
    mod = carrier * 1.5
    index = 4.2 * decay(t, 0.004)
    fm = np.sin(2.0 * np.pi * carrier * t + index * np.sin(2.0 * np.pi * mod * t))
    shimmer = 0.25 * np.sin(2.0 * np.pi * 3620.0 * t) * decay(t, 0.0025)
    click = 0.20 * highpass(noise(len(t)), 3000.0) * decay(t, 0.0012)
    return (fm + shimmer + click) * env


def impact_light():
    """Short scuff: a bright noise scrape over a small metallic body."""
    t = t_axis(0.130)
    body = partials(t, [430.0, 712.0, 1180.0], [1.0, 0.55, 0.3], [0.030, 0.022, 0.014])
    scrape = 0.7 * bandpass(noise(len(t)), 1400.0, 6500.0) * decay(t, 0.020)
    return body * decay(t, 0.045) + scrape


def impact_heavy():
    """Low thud plus a metallic ring: the sound of a panel taking a real hit."""
    t = t_axis(0.480)
    # Thud with a pitch drop, 115 Hz down to 58 Hz.
    f = 58.0 + 57.0 * decay(t, 0.045)
    thud = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * decay(t, 0.085)
    ring = partials(
        t,
        [318.0, 527.0, 869.0, 1345.0, 2110.0],
        [0.55, 0.44, 0.32, 0.22, 0.12],
        [0.170, 0.140, 0.110, 0.075, 0.050],
    )
    crack = 0.8 * bandpass(noise(len(t)), 900.0, 7000.0) * decay(t, 0.012)
    return 1.25 * thud + 0.85 * ring + crack


def flipper_fire():
    """Pneumatic hiss for 120 ms, then the clunk of the arm hitting its stop."""
    total = 0.360
    t = t_axis(total)
    x = np.zeros_like(t)

    hiss_n = int(0.120 * SR)
    th = t[:hiss_n]
    # Swells in, snaps off when the ram reaches the end of its stroke.
    swell = np.clip(th / 0.030, 0.0, 1.0) * (1.0 - np.clip((th - 0.080) / 0.040, 0.0, 1.0))
    hiss = bandpass(noise(hiss_n), 2200.0, 9000.0) * swell
    x[:hiss_n] += 0.85 * hiss

    clunk_at = int(0.118 * SR)
    tc = t_axis(total - 0.118)
    clunk = partials(
        tc,
        [96.0, 214.0, 402.0, 741.0, 1290.0],
        [1.0, 0.6, 0.42, 0.26, 0.14],
        [0.055, 0.045, 0.035, 0.022, 0.014],
    )
    clunk += 0.6 * lowpass(noise(len(tc)), 1600.0) * decay(tc, 0.010)
    x[clunk_at:clunk_at + len(tc)] += 1.4 * clunk
    return x


def wheel_off():
    """A wheel shears off: rubbery thump, then two settling bounces."""
    total = 0.520
    t = t_axis(total)
    x = np.zeros_like(t)
    for offset, gain in ((0.0, 1.0), (0.185, 0.42), (0.320, 0.18)):
        tb = t_axis(total - offset)
        thump = np.sin(2.0 * np.pi * (72.0 + 40.0 * decay(tb, 0.020)) * tb) * decay(tb, 0.045)
        rub = lowpass(noise(len(tb)), 900.0) * decay(tb, 0.018)
        seg = gain * (thump + 0.55 * rub)
        i = int(offset * SR)
        x[i:i + len(seg)] += seg
    return x


def panel_off():
    """Armour panel clatter: five metallic hits at irregular spacings."""
    total = 0.620
    t = t_axis(total)
    x = np.zeros_like(t)
    offsets = [0.0, 0.052, 0.128, 0.245, 0.392]
    gains = [1.0, 0.62, 0.48, 0.34, 0.20]
    for offset, gain in zip(offsets, gains):
        tb = t_axis(total - offset)
        base = RNG.uniform(360.0, 620.0)
        hit = partials(
            tb,
            [base, base * 1.73, base * 2.61, base * 4.12],
            [1.0, 0.6, 0.38, 0.2],
            [0.055, 0.040, 0.026, 0.016],
        )
        hit += 0.5 * bandpass(noise(len(tb)), 1200.0, 8000.0) * decay(tb, 0.008)
        i = int(offset * SR)
        x[i:i + len(hit)] += gain * hit
    return x


def periodic_noise(n, lo, hi):
    """Noise that is exactly periodic over n samples, so it loops without a seam."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    band = (freqs >= lo) & (freqs <= hi)
    spec[band] = np.exp(1j * RNG.uniform(0.0, 2.0 * np.pi, int(band.sum())))
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def motor_loop():
    """Seamless 1 s drive hum. Pitch follows throttle at playback time.

    Every component has a period that divides one second (integer frequencies and
    frequency-domain noise), so sample 0 continues from the last sample exactly.
    No fades: a fade would put a dip at the seam.
    """
    n = SR  # exactly 1.000 s
    t = np.arange(n) / SR
    x = np.zeros(n)
    f0 = 55  # integer Hz, so 55 whole cycles fit in the second
    for h, amp in ((1, 1.0), (2, 0.62), (3, 0.30), (4, 0.20), (5, 0.11), (7, 0.07), (9, 0.04)):
        x += amp * np.sin(2.0 * np.pi * (f0 * h) * t + RNG.uniform(0.0, 2.0 * np.pi))
    # Gearbox whine, still an integer frequency.
    x += 0.09 * np.sin(2.0 * np.pi * 440.0 * t + RNG.uniform(0.0, 2.0 * np.pi))
    # Brush/bearing hash, periodic by construction.
    x += 0.16 * periodic_noise(n, 300.0, 4200.0)
    # Slow loading wobble; 3 and 7 Hz both complete whole cycles in the second.
    wobble = 1.0 + 0.06 * np.sin(2.0 * np.pi * 3.0 * t) + 0.035 * np.sin(2.0 * np.pi * 7.0 * t)
    x *= wobble
    return x


def countdown_tick():
    """Dry blip for 3, 2, 1. The arena plays it at a higher pitch for FIGHT."""
    t = t_axis(0.090)
    env = decay(t, 0.018) * np.clip(t / 0.0015, 0.0, 1.0)
    tone = np.sin(2.0 * np.pi * 880.0 * t) + 0.35 * np.sin(2.0 * np.pi * 1760.0 * t)
    tick = 0.3 * highpass(noise(len(t)), 2500.0) * decay(t, 0.003)
    return tone * env + tick


def bell():
    """Struck bell, 1.5 s. Inharmonic partials on a 520 Hz prime, slight beating."""
    t = t_axis(1.500)
    f0 = 520.0
    ratios = [0.50, 1.00, 1.19, 1.50, 2.00, 2.53, 3.01, 4.11, 5.43]
    amps = [0.55, 1.00, 0.62, 0.48, 0.40, 0.26, 0.20, 0.12, 0.07]
    taus = [1.05, 0.80, 0.55, 0.45, 0.32, 0.22, 0.17, 0.10, 0.07]
    x = np.zeros_like(t)
    for r, a, tau in zip(ratios, amps, taus):
        f = f0 * r
        phase = RNG.uniform(0.0, 2.0 * np.pi)
        # Detuned twin gives the slow beat a real bell has.
        x += a * decay(t, tau) * (
            np.sin(2.0 * np.pi * f * t + phase)
            + 0.7 * np.sin(2.0 * np.pi * f * (1.0 + 0.0016) * t + phase)
        )
    strike = 0.9 * bandpass(noise(len(t)), 1500.0, 9000.0) * decay(t, 0.006)
    return x + strike


def ko_tick():
    """The knockout count. Dull, urgent, no sparkle."""
    t = t_axis(0.140)
    env = decay(t, 0.030) * np.clip(t / 0.002, 0.0, 1.0)
    tone = np.sin(2.0 * np.pi * 300.0 * t) + 0.4 * np.sin(2.0 * np.pi * 452.0 * t)
    knock = 0.5 * lowpass(noise(len(t)), 1400.0) * decay(t, 0.006)
    return tone * env + knock


def spikes():
    """Short mechanical rise: air, a rising metal scrape, then the top stop."""
    total = 0.420
    t = t_axis(total)
    x = np.zeros_like(t)

    rise_n = int(0.300 * SR)
    tr = t[:rise_n]
    air = bandpass(noise(rise_n), 900.0, 5200.0) * np.clip(tr / 0.020, 0.0, 1.0) * 0.7
    # Rising scrape, 180 Hz up to 620 Hz.
    f = 180.0 + 440.0 * (tr / 0.300) ** 1.4
    scrape = 0.55 * np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.clip(tr / 0.030, 0.0, 1.0)
    x[:rise_n] += air + scrape

    stop_at = int(0.298 * SR)
    ts = t_axis(total - 0.298)
    stop = partials(
        ts,
        [128.0, 268.0, 497.0, 930.0],
        [1.0, 0.55, 0.34, 0.18],
        [0.038, 0.028, 0.018, 0.011],
    )
    x[stop_at:stop_at + len(stop)] += 1.3 * stop
    return x


# ---------------------------------------------------------------- main


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Roboteer placeholder sounds -> %s" % OUT_DIR)

    write("bolt_collect.wav", bolt_collect(), in_ms=0.3, out_ms=3.0)
    write("impact_light.wav", impact_light(), in_ms=0.3, out_ms=5.0)
    write("impact_heavy.wav", impact_heavy(), in_ms=0.3, out_ms=12.0)
    write("flipper_fire.wav", flipper_fire(), in_ms=1.0, out_ms=12.0)
    write("wheel_off.wav", wheel_off(), in_ms=0.5, out_ms=14.0)
    write("panel_off.wav", panel_off(), in_ms=0.5, out_ms=14.0)
    write("countdown_tick.wav", countdown_tick(), in_ms=0.5, out_ms=6.0)
    write("bell.wav", bell(), in_ms=0.5, out_ms=40.0)
    write("ko_tick.wav", ko_tick(), in_ms=0.5, out_ms=8.0)
    write("spikes.wav", spikes(), in_ms=1.0, out_ms=12.0)

    loop = motor_loop()
    write("motor_loop.wav", loop, do_fade=False)

    # Prove the loop seam: the wrap-around step must be no bigger than a normal
    # sample to sample step inside the file, or it will click once per second.
    norm = normalise(np.asarray(loop, dtype=np.float64))
    inner = float(np.max(np.abs(np.diff(norm))))
    seam = abs(float(norm[0] - norm[-1]))
    print("motor_loop seam step %.6f vs max inner step %.6f  (%s)"
          % (seam, inner, "seamless" if seam <= inner else "CLICKS"))
    if seam > inner:
        raise SystemExit("motor_loop.wav is not seamless")


if __name__ == "__main__":
    main()
