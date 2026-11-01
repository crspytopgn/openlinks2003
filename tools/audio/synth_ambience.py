#!/usr/bin/env python3
"""Synthesises the quiet background layers of a golf course in game/assets/sounds/.

Real course and broadcast sound is mostly quiet: air and leaves, a road or a
greenkeeper's mower somewhere far off, and at a tournament the murmur of the
gallery. Field recordings of those are hard to find under a free licence
without birdsong or speech on them, so these are built from noise, the way
a sound designer builds a distant bed:

  amb_traffic  a far road: brown noise rolled off above a few hundred hertz,
               swelling gently as cars pass. Loops seamlessly.
  amb_mower    one pass of a distant ride-on mower: a single-cylinder engine
               at about 3,000 rpm (firing pulses of filtered noise), its load
               and pitch wandering, coming nearer and going away. Not looped.
  amb_murmur   a tournament gallery talking among itself, heard from across
               the tee: thirty voices of formant-filtered noise and buzz,
               each in phrases of four to five syllables a second with
               pauses. Loops seamlessly.

    python3 tools/audio/synth_ambience.py

Needs numpy and ffmpeg (with libvorbis). Deterministic (fixed seeds).
"""
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "game", "assets", "sounds")
SR = 22050


def shaped_noise(n, rng, gain_at):
    """Noise of n samples whose spectrum follows gain_at(freqs). Periodic in n,
    so it loops without a seam."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec *= gain_at(f)
    return np.fft.irfft(spec, n)


def bandpass(f, lo, hi, order=2):
    """Smooth band-pass gain: Butterworth-like skirts."""
    g = np.ones_like(f)
    with np.errstate(divide="ignore"):
        g /= np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    g /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    return g


def filt(x, gain_at):
    spec = np.fft.rfft(x)
    spec *= gain_at(np.fft.rfftfreq(len(x), 1.0 / SR))
    return np.fft.irfft(spec, len(x))


def norm(x, rms_db, peak_db=-3.0):
    x = x * (10 ** (rms_db / 20) / (np.sqrt((x ** 2).mean()) + 1e-12))
    peak = np.abs(x).max()
    if peak > 10 ** (peak_db / 20):
        x *= 10 ** (peak_db / 20) / peak
    return x


def traffic(seconds=32.0):
    rng = np.random.default_rng(31)
    n = int(seconds * SR)
    # Tyre and engine roar from far away: most energy 60 to 400 Hz, the air
    # takes the top off.
    bed = shaped_noise(n, rng, lambda f: bandpass(f, 50.0, 380.0, 2) / np.sqrt(np.maximum(f, 20.0) / 20.0))
    t = np.arange(n) / SR
    # Cars passing: slow swells, a whole number of cycles in the loop.
    swell = np.ones(n)
    for cycles, depth in ((3, 0.35), (5, 0.25), (8, 0.15)):
        swell += depth * np.sin(2 * np.pi * cycles * t / seconds + rng.uniform(0, 2 * np.pi))
    hiss = shaped_noise(n, rng, lambda f: bandpass(f, 500.0, 1800.0, 2)) * 0.12
    return norm(bed * np.maximum(swell, 0.2) + hiss * swell, -30.0)


def mower(seconds=34.0):
    rng = np.random.default_rng(57)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    # Engine speed wanders with the load (cutting, turning at the end of a
    # stripe): firing rate about 25 Hz.
    wander = np.cumsum(rng.standard_normal(n)) / SR
    wander = filt(wander - wander.mean(), lambda f: 1.0 / (1.0 + (f / 0.3) ** 2))
    rate = 25.0 * (1.0 + 0.06 * wander / (np.abs(wander).max() + 1e-9) + 0.03 * np.sin(2 * np.pi * t / 9.0))
    phase = np.cumsum(rate) / SR
    fire = np.diff(np.floor(phase), prepend=0.0) > 0
    pulses = np.zeros(n)
    idx = np.nonzero(fire)[0]
    pulses[idx] = 1.0 + 0.25 * rng.standard_normal(len(idx))
    # Each firing: a short thump of exhaust, then the blade's hum under it.
    k = np.arange(int(0.03 * SR)) / SR
    thump = np.exp(-k / 0.006) * np.sin(2 * np.pi * 150.0 * k)
    exhaust = np.convolve(pulses, thump)[:n]
    noise = shaped_noise(n, rng, lambda f: bandpass(f, 120.0, 900.0, 2))
    engine = exhaust * (1.0 + 0.6 * noise / (np.abs(noise).max() + 1e-9))
    blade = np.sin(2 * np.pi * np.cumsum(rate * 2.0) / SR) * 0.15
    sound = engine + blade
    # Far off: the air and the ground take the top.
    sound = filt(sound, lambda f: 1.0 / np.sqrt(1.0 + (f / 900.0) ** 4))
    # Comes nearer, works a stripe, goes away.
    env = np.interp(t, [0, 9, 14, 22, 28, seconds], [0.0, 0.55, 1.0, 0.9, 0.4, 0.0]) ** 1.5
    return norm(sound * env, -26.0)


def murmur(seconds=30.0, voices=30):
    rng = np.random.default_rng(83)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    mix = np.zeros(n)
    for _ in range(voices):
        f0 = rng.uniform(95.0, 230.0)
        f1 = rng.uniform(350.0, 800.0)
        f2 = rng.uniform(1000.0, 2100.0)
        # Voiced buzz (with a little intonation) and breath, through two
        # formants.
        pitch = f0 * (1.0 + 0.06 * np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * t + rng.uniform(0, 6.3)))
        ph = np.cumsum(pitch) / SR
        buzz = (ph % 1.0) - 0.5
        breath = rng.standard_normal(n) * 0.25
        src = buzz + breath
        voice = filt(src, lambda f: 1.4 * bandpass(f, f1 * 0.7, f1 * 1.3, 2) + bandpass(f, f2 * 0.8, f2 * 1.25, 2))
        # Phrases of syllables (4 to 5 a second) with pauses, laid round the
        # loop so it wraps.
        gate = np.zeros(n)
        pos = rng.uniform(0.0, seconds)
        end = pos + seconds
        rate = rng.uniform(3.8, 5.2)
        while pos < end:
            phrase = rng.uniform(0.8, 3.0)
            m = int(phrase * SR)
            k = np.arange(m) / SR
            syll = 0.5 - 0.5 * np.cos(2 * np.pi * rate * k)
            syll *= np.minimum(1.0, np.minimum(k, phrase - k) / 0.12)
            syll *= rng.uniform(0.6, 1.0)
            start = int(pos * SR)
            ids = (start + np.arange(m)) % n
            np.add.at(gate, ids, syll)
            pos += phrase + rng.uniform(0.4, 2.5)
        mix += voice / (np.sqrt((voice ** 2).mean()) + 1e-9) * gate * rng.uniform(0.4, 1.0)
    # Heard from across the tee: soften the top a little.
    mix = filt(mix, lambda f: 1.0 / np.sqrt(1.0 + (f / 2600.0) ** 4) * bandpass(f, 120.0, 20000.0, 1))
    return norm(mix, -28.0)


def encode(x, name):
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "0", "-map_metadata", "-1", path],
                   input=x.astype(np.float32).tobytes(), check=True)
    print(f"{name:12s} {len(x) / SR:5.1f} s {os.path.getsize(path) / 1024:6.1f} KB")


def main():
    encode(traffic(), "amb_traffic")
    encode(mower(), "amb_mower")
    encode(murmur(), "amb_murmur")


if __name__ == "__main__":
    sys.exit(main())
