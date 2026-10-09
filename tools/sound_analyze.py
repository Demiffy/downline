# Sound analysis: measure recordings or our own synthesized sounds (dump them with tests/sfx_dump.gd)
# to compare envelope, spectrum, modes, pitch and rhythm. Needs numpy, scipy, matplotlib.
"""Analyse WAV clips: envelope, spectrum, modes, pitch, rhythm. Writes a report and spectrograms.
usage: python analyze.py <out_dir> <wav> [wav ...]
"""
import sys, os, struct, json
import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_wav(path, max_secs=12.0):
    b = open(path, "rb").read()
    assert b[:4] == b"RIFF" and b[8:12] == b"WAVE", path
    i = 12
    fmt = None
    data = None
    while i + 8 <= len(b):
        cid = b[i:i + 4]
        size = struct.unpack("<I", b[i + 4:i + 8])[0]
        body = b[i + 8:i + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
            if fmt[0] == 0xFFFE and len(body) >= 26:   # extensible: real format in the subformat GUID
                fmt = (struct.unpack("<H", body[24:26])[0],) + fmt[1:]
        elif cid == b"data":
            data = body   # (may be cut short: a partial download)
            break
        i += 8 + size + (size & 1)
    tag, ch, rate, _, _, bits = fmt
    n = len(data) // (bits // 8 * ch) * (bits // 8 * ch)
    data = data[:n]
    if tag == 3:
        x = np.frombuffer(data, "<f4" if bits == 32 else "<f8").astype(np.float64)
    elif bits == 16:
        x = np.frombuffer(data, "<i2").astype(np.float64) / 32768.0
    elif bits == 24:
        a = np.frombuffer(data, np.uint8).reshape(-1, 3)
        v = (a[:, 0].astype(np.int32) | (a[:, 1].astype(np.int32) << 8) | (a[:, 2].astype(np.int32) << 16))
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v.astype(np.float64) / (1 << 23)
    elif bits == 32:
        x = np.frombuffer(data, "<i4").astype(np.float64) / 2 ** 31
    elif bits == 8:
        x = (np.frombuffer(data, np.uint8).astype(np.float64) - 128) / 128
    x = x.reshape(-1, ch).mean(axis=1)
    x = x[: int(max_secs * rate)]
    return x, rate


def envelope(x, rate, hop=0.005):
    h = max(1, int(hop * rate))
    frames = len(x) // h
    e = np.sqrt(np.mean(x[: frames * h].reshape(frames, h) ** 2, axis=1) + 1e-12)
    return e, h / rate


def band_energies(x, rate):
    f, p = signal.welch(x, rate, nperseg=min(8192, len(x)))
    bands = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    out = {}
    tot = np.sum(p) + 1e-20
    for c in bands:
        lo, hi = c / np.sqrt(2), c * np.sqrt(2)
        m = (f >= lo) & (f < hi)
        out[int(c)] = round(float(10 * np.log10(np.sum(p[m]) / tot + 1e-12)), 1)
    centroid = float(np.sum(f * p) / tot)
    cum = np.cumsum(p) / tot
    roll85 = float(f[np.searchsorted(cum, 0.85)])
    flat = float(np.exp(np.mean(np.log(p + 1e-20))) / (np.mean(p) + 1e-20))
    return out, centroid, roll85, flat, f, p


def modes(x, rate, start, n=8):
    """Strongest spectral peaks after the hit, and how fast each dies away."""
    seg = x[start: start + int(0.6 * rate)]
    if len(seg) < 2048:
        return []
    w = np.hanning(len(seg))
    sp = np.abs(np.fft.rfft(seg * w))
    fr = np.fft.rfftfreq(len(seg), 1 / rate)
    m = (fr > 40) & (fr < 12000)
    pk, prop = signal.find_peaks(sp * m, distance=max(1, int(30 / (fr[1] - fr[0]))), prominence=np.max(sp[m]) * 0.04)
    pk = pk[np.argsort(sp[pk])[::-1][:n]]
    res = []
    for k in sorted(pk, key=lambda k: fr[k]):
        f0 = fr[k]
        # decay: band-pass round the mode and fit the log envelope
        lo, hi = max(20, f0 * 0.94), min(rate / 2 - 100, f0 * 1.06)
        sos = signal.butter(2, [lo, hi], "band", fs=rate, output="sos")
        y = signal.sosfilt(sos, x[start: start + int(1.5 * rate)])
        e, dt = envelope(y, rate, 0.01)
        e = e / (e.max() + 1e-12)
        i0 = int(np.argmax(e))
        tail = e[i0:]
        good = tail > 0.02
        if good.sum() > 4:
            t = np.arange(len(tail))[good] * dt
            slope = np.polyfit(t, np.log(tail[good]), 1)[0]
        else:
            slope = -60
        res.append({"hz": round(float(f0), 1), "amp": round(float(sp[k] / sp[pk].max()), 3), "decay": round(float(-slope), 1)})
    return res


def pitch_track(x, rate, fmin=40, fmax=1500):
    hop = int(0.02 * rate)
    win = int(0.06 * rate)
    out = []
    for i in range(0, len(x) - win, hop):
        s = x[i:i + win] * np.hanning(win)
        if np.sqrt(np.mean(s ** 2)) < 1e-3:
            out.append(0.0)
            continue
        ac = np.correlate(s, s, "full")[win - 1:]
        ac /= ac[0] + 1e-12
        lo, hi = int(rate / fmax), int(rate / fmin)
        k = lo + int(np.argmax(ac[lo:hi]))
        out.append(rate / k if ac[k] > 0.3 else 0.0)
    return np.array(out)


def onsets(e, dt):
    d = np.diff(np.log(e + 1e-6))
    pk, _ = signal.find_peaks(d, height=0.6, distance=int(0.12 / dt))
    return (pk * dt).tolist()


def analyse(path, out_dir):
    name = os.path.splitext(os.path.basename(path))[0]
    x, rate = read_wav(path)
    x = x - np.mean(x)
    peak = np.max(np.abs(x)) + 1e-12
    x = x / peak
    e, dt = envelope(x, rate)
    i_pk = int(np.argmax(e))
    above = np.where(e > e.max() * 0.1)[0]
    attack = (i_pk - above[0]) * dt if len(above) else 0.0
    after = e[i_pk:]
    t60 = next((k * dt for k, v in enumerate(after) if v < e.max() * 0.001), len(after) * dt)
    t20 = next((k * dt for k, v in enumerate(after) if v < e.max() * 0.1), len(after) * dt)
    bands, centroid, roll, flat, f, p = band_energies(x, rate)
    md = modes(x, rate, max(0, i_pk * int(dt * rate) - int(0.002 * rate)))
    pt = pitch_track(x, rate)
    voiced = pt[pt > 0]
    ons = onsets(e, dt)
    # Slow amplitude modulation (engine firing, a siren's rise and fall, footsteps).
    em = e - np.mean(e)
    fm, pm = signal.welch(em, 1 / dt, nperseg=min(1024, len(em)))
    am = float(fm[1 + np.argmax(pm[1:])]) if len(pm) > 2 else 0.0
    rep = {
        "name": name, "rate": rate, "secs": round(len(x) / rate, 2),
        "attack_ms": round(attack * 1000, 1), "decay_to_-20dB_ms": round(t20 * 1000), "decay_to_-60dB_ms": round(t60 * 1000),
        "centroid_hz": round(centroid), "rolloff85_hz": round(roll), "flatness": round(flat, 3),
        "bands_db": bands, "modes": md,
        "pitch_hz_median": round(float(np.median(voiced)), 1) if len(voiced) > 5 else None,
        "pitch_range": [round(float(np.percentile(voiced, 5)), 1), round(float(np.percentile(voiced, 95)), 1)] if len(voiced) > 5 else None,
        "voiced_frac": round(float(len(voiced) / max(1, len(pt))), 2),
        "onsets_s": [round(o, 3) for o in ons[:24]],
        "am_hz": round(am, 2),
    }
    fig, ax = plt.subplots(2, 1, figsize=(9, 5), gridspec_kw={"height_ratios": [1, 2]})
    ax[0].plot(np.arange(len(e)) * dt, 20 * np.log10(e + 1e-6))
    ax[0].set_ylim(-70, 3)
    ax[0].set_title(name)
    ff, tt, S = signal.spectrogram(x, rate, nperseg=1024, noverlap=768)
    ax[1].pcolormesh(tt, ff, 10 * np.log10(S + 1e-12), shading="auto", vmin=-110, vmax=-20)
    ax[1].set_ylim(0, min(rate / 2, 12000))
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, name + ".png"), dpi=70)
    plt.close(fig)
    return rep


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    reps = []
    for p in sys.argv[2:]:
        try:
            r = analyse(p, out)
            reps.append(r)
            print(json.dumps(r))
        except Exception as ex:
            print("ERR", p, ex)
    json.dump(reps, open(os.path.join(out, "report.json"), "w"), indent=1)
