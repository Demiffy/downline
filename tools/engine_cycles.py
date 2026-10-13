# Engine recordings into numbers the game can rebuild an engine from (sfx.gd _engine_cycles), without
# shipping the recording. An engine is a sound that repeats once per firing: cut a steady stretch of a
# recording into its firing cycles (pitch-synchronous, each lined up on the last by cross-correlation),
# average them into the engine's own waveform for one cycle (what's the same every time), and measure
# what isn't: how much the cycles wander in length and strength, and the noise left over (its spectrum
# as an FIR filter, and how it swells and fades through each cycle). Writes the numbers as GDScript and
# a WAV of the rebuild to compare. Needs numpy, scipy.
"""usage:
  python engine_cycles.py track <wav>                          firing rate, second by second (pick a steady stretch)
  python engine_cycles.py cycles <wav> <start s> <secs> <name> <out_dir> [lo_hz hi_hz]
"""
import sys, os, json
import numpy as np
from scipy import signal
from scipy.io import wavfile


def load(path):
    rate, x = wavfile.read(path)
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x /= max(1e-9, np.abs(x).max())
    return rate, x


def f0_of(seg, rate, lo, hi):
    """The firing rate: the strongest repetition of the low end, between lo and hi Hz."""
    b, a = signal.butter(4, min(0.99, 600.0 / (rate / 2)), "low")
    y = signal.filtfilt(b, a, seg)
    y = y - y.mean()
    ac = signal.correlate(y, y, "full")[len(y) - 1:]
    ac /= max(1e-9, ac[0])
    lag0, lag1 = int(rate / hi), int(rate / lo)
    k = lag0 + int(np.argmax(ac[lag0:lag1]))
    # prefer the shortest period that's nearly as strong (not twice the true period)
    for div in (4, 3, 2):
        kk = int(round(k / div))
        if kk >= lag0:
            win = ac[max(lag0, kk - 3):kk + 4]
            if len(win) and win.max() > 0.8 * ac[k]:
                k = max(lag0, kk - 3) + int(np.argmax(win))
                break
    return rate / k, float(ac[k])


def track(path, lo=15.0, hi=140.0):
    rate, x = load(path)
    for s in range(0, int(len(x) / rate)):
        seg = x[s * rate:(s + 1) * rate]
        if len(seg) < rate // 2:
            break
        f, strength = f0_of(seg, rate, lo, hi)
        rms = float(np.sqrt(np.mean(seg ** 2)))
        print("%3d s  %6.1f Hz  periodic %.2f  level %.3f" % (s, f, strength, rms))


def cycles(path, start, secs, name, out, lo=15.0, hi=140.0):
    rate, x = load(path)
    seg = x[int(start * rate):int((start + secs) * rate)]
    seg = seg - np.mean(seg)
    f0, strength = f0_of(seg, rate, lo, hi)
    period = rate / f0
    L = int(round(period))
    # Cycle boundaries: step a period on, then slide (within 12%) to where it best matches the template.
    b, a = signal.butter(4, min(0.99, 1500.0 / (rate / 2)), "low")
    guide = signal.filtfilt(b, a, seg)
    marks = [int(np.argmax(guide[:L]))]
    template = guide[marks[0]:marks[0] + L].copy()
    while marks[-1] + int(period * 1.15) + L < len(seg):
        p = marks[-1] + int(round(period))
        w = int(period * 0.12)
        best, best_c = p, -1e9
        for q in range(p - w, p + w + 1):
            c = float(np.dot(guide[q:q + L], template))
            if c > best_c:
                best, best_c = q, c
        marks.append(best)
        template = 0.9 * template + 0.1 * guide[best:best + L]
    lens = np.diff(marks)
    # Each cycle stretched to L samples, then averaged: the engine's own waveform.
    cyc = []
    for i in range(len(marks) - 1):
        piece = seg[marks[i]:marks[i + 1]]
        cyc.append(np.interp(np.linspace(0, len(piece) - 1, L), np.arange(len(piece)), piece))
    cyc = np.array(cyc)
    mean = cyc.mean(axis=0)
    gains = np.array([np.dot(c, mean) / max(1e-9, np.dot(mean, mean)) for c in cyc])
    resid = cyc - gains[:, None] * mean
    harm = float(np.sum((gains[:, None] * mean) ** 2))
    noise = float(np.sum(resid ** 2))
    # The noise: its spectrum (a 63-tap FIR), and its loudness through the cycle (16 steps).
    flat = resid.flatten()
    fw, pw = signal.welch(flat, rate, nperseg=512)
    mag = np.sqrt(pw / max(1e-12, pw.max()))
    taps = signal.firwin2(63, fw / (rate / 2), mag)
    phase_env = np.sqrt(np.mean(resid.reshape(len(resid), 16, -1)[:, :, :] ** 2, axis=(0, 2))) if L % 16 == 0 else \
        np.array([np.sqrt(np.mean(resid[:, int(k * L / 16):int((k + 1) * L / 16)] ** 2)) for k in range(16)])
    phase_env /= max(1e-9, phase_env.max())
    info = {
        "name": name, "f0": round(f0, 2), "periodicity": round(strength, 3), "cycles": len(cyc),
        "len_jitter": round(float(np.std(lens) / np.mean(lens)), 4), "gain_jitter": round(float(np.std(gains) / np.mean(gains)), 4),
        "noise_ratio": round(noise / max(1e-12, harm + noise), 3),
    }
    print(json.dumps(info))
    os.makedirs(out, exist_ok=True)
    peak = max(1e-9, np.abs(mean).max())
    gd = ["## %s: measured by tools/engine_cycles.py from a recording (%d cycles at %.2f Hz)." % (name, len(cyc), f0),
          "const %s := {" % name.upper(),
          '\t"f0": %.3f, "len_jitter": %.4f, "gain_jitter": %.4f, "noise": %.4f,' % (f0, info["len_jitter"], info["gain_jitter"], np.sqrt(noise / max(1e-12, harm))),
          '\t"cycle": [%s],' % ", ".join("%.4f" % v for v in mean / peak),
          '\t"noise_fir": [%s],' % ", ".join("%.5f" % v for v in taps),
          '\t"noise_env": [%s],' % ", ".join("%.3f" % v for v in phase_env),
          "}"]
    open(os.path.join(out, name + ".gd.txt"), "w").write("\n".join(gd) + "\n")
    # A rebuild in Python, to hear and measure against the recording.
    rng = np.random.default_rng(1)
    outv = np.zeros(int(rate * 6))
    t = 0
    nz_scale = np.sqrt(noise / max(1e-12, harm))
    while t + L * 2 < len(outv):
        ln = int(round(L * (1 + rng.normal(0, info["len_jitter"]))))
        c = np.interp(np.linspace(0, L - 1, ln), np.arange(L), mean / peak) * (1 + rng.normal(0, info["gain_jitter"]))
        nz = signal.lfilter(taps, 1.0, rng.normal(0, 1, ln + 63))[63:]
        env = np.interp(np.linspace(0, 15, ln), np.arange(16), phase_env)
        nz = nz / max(1e-9, np.std(nz)) * np.std(mean / peak) * nz_scale * env
        outv[t:t + ln] += c + nz
        t += ln
    outv /= max(1e-9, np.abs(outv).max())
    wavfile.write(os.path.join(out, name + "_rebuild.wav"), rate, (outv * 32000).astype(np.int16))
    wavfile.write(os.path.join(out, name + "_source.wav"), rate, (seg / max(1e-9, np.abs(seg).max()) * 32000).astype(np.int16))


if __name__ == "__main__":
    if sys.argv[1] == "track":
        track(sys.argv[2])
    else:
        a = sys.argv
        cycles(a[2], float(a[3]), float(a[4]), a[5], a[6], *(float(v) for v in a[7:9]))
