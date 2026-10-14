# A real recording into a "sound print": numbers the game rebuilds the sound from (sfx.gd _from_print),
# without shipping the recording. Three parts, measured from the recording:
#   tracks  the tonal part: each sinusoid's frequency and level through time (peak tracking)
#   bands   what's left (the noise): its level in 32 bands, 86 times a second
#   env     the noise's loudness every 2 ms, so attacks stay sharp and crackle stays crackly
# The rebuild here is the same algorithm as the game's, sample for sample apart from the dice, so what
# it writes (name_rebuild.wav) is what the game plays. Needs numpy, scipy; ffmpeg for search/fetch.
"""usage:
  python sound_print.py search <query words...>             CC0 recordings on Freesound (id, secs, downloads, title)
  python sound_print.py searches <file of name|query lines>  the same, many at once
  python sound_print.py fetch <freesound id> <out.wav>       its preview, as 22050 Hz mono
  python sound_print.py print <wav> <start s> <secs> <name> <out_dir> [loop] [match.wav]
  python sound_print.py bundle <prints_dir> <sources.json> <out.gd>   every print into one GDScript file
  python sound_print.py build <sources.json> <ref_dir> <prints_dir> <old_dir> [names...]
       fetch what's missing and print every sound listed (or just those named); old_dir: the old sounds' WAVs.
       A sound may list several sources (takes); each: id, start, secs, [loop], [hp/lp Hz: filtered first],
       [tail: false, a one-shot cut at secs even if it's still dying away there], [fade: s, its fade out], [drive: dB, peaks squeezed so it plays louder]
       (start "auto": the loudest event; "steady": the evenest stretch, for loops; "peak:-4": from 4 s
        before the loudest moment; match.wav: the old sound, to keep its loudness in the mix)
"""
import sys, os, re, json, zlib, base64, struct, subprocess, urllib.request
import numpy as np
from scipy import signal, ndimage
from scipy.io import wavfile

SR = 22050
N = 512          # noise frames: 512 samples, every 256
HOP = 256
NB = 32          # noise bands
TN = 1024        # tonal analysis window, every 128
THOP = 128
ENV = 44         # fine envelope: one value every 44 samples (2 ms)
NL = 2048        # the low end (under SPLIT Hz) apart: finer in pitch, slower in time
HOPL = 512
LBINS = 40       # its bins kept: up to 430 Hz
ENVL = 132       # its envelope: every 6 ms
SPLIT = 350.0
EB = [1500.0, 5000.0]   # the noise over SPLIT gets a 2 ms envelope in each of three ranges, split here (one
                        # envelope for all of it let the loud lows' swings pump the quiet highs: hiss)


def masks(nbins, rate):
    """Amplitude crossfades (they add up to 1) over nbins rfft bins: the three ranges of EB."""
    f = np.arange(nbins) * rate / (2.0 * (nbins - 1))
    def rise(e):   # 0 below e/1.25, 1 over e*1.25, a raised cosine between (in log frequency)
        t = np.clip((np.log(np.maximum(f, 1.0)) - np.log(e / 1.25)) / (np.log(e * 1.25) - np.log(e / 1.25)), 0.0, 1.0)
        return 0.5 - 0.5 * np.cos(np.pi * t)
    r1, r2 = rise(EB[0]), rise(EB[1])
    return [1.0 - r1, r1 - r2, r2]
UA = {"User-Agent": "Mozilla/5.0 (downline sound research)"}


def edges():
    """Band edges in FFT bins (N=512): even on the ERB scale from 40 Hz up, at least one bin each."""
    erb = lambda f: 21.4 * np.log10(1 + 0.00437 * f)
    inv = lambda e: (10 ** (e / 21.4) - 1) / 0.00437
    hz = inv(np.linspace(erb(40.0), erb(SR / 2), NB + 1))
    b = np.round(hz / (SR / N)).astype(int)
    b[0] = 0
    for i in range(1, len(b)):
        b[i] = max(b[i], b[i - 1] + 1)
    b[-1] = N // 2 + 1
    return b


EDGES = edges()


# --- finding recordings ------------------------------------------------------------------------------

def get(url):
    """The page or file at url; turned away for asking too often (429), waits and asks again."""
    import time, urllib.error
    for wait in (0, 2, 4, 8, 16, 30):
        time.sleep(wait)
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
    raise RuntimeError("still turned away (429): " + url)


def search(q):
    url = "https://freesound.org/search/?q=%s&f=license%%3A%%22Creative+Commons+0%%22&s=Downloads+descending" % urllib.parse.quote_plus(q)
    html = get(url).decode("utf8", "replace")
    out = []
    for m in re.finditer(r'data-sound-id="(\d+)"\s+data-username="([^"]*)".*?data-mp3="([^"]+)".*?data-title="([^"]*)"\s+data-duration="([\d.]+)".*?data-num-downloads="(\d+)"', html, re.S):
        out.append({"id": int(m[1]), "user": m[2], "mp3": m[3], "title": m[4], "secs": float(m[5]), "downloads": int(m[6])})
    return out


def fetch(sid, path, mp3=None):
    if mp3 is None:
        page = get("https://freesound.org/s/%d/" % sid).decode("utf8", "replace")
        mp3 = re.search(r'https://cdn\.freesound\.org/previews/[^"]+-lq\.mp3', page)[0]
    hq = mp3.replace("-lq.mp3", "-hq.mp3")
    tmp = path + ".mp3"
    for u in (hq, mp3):
        try:
            open(tmp, "wb").write(get(u))
            break
        except Exception:
            continue
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-ac", "1", "-ar", str(SR), path], check=True)
    os.remove(tmp)


# --- measuring ---------------------------------------------------------------------------------------

def load(path):
    rate, x = wavfile.read(path)
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if rate != SR:
        x = signal.resample_poly(x, SR, rate)
    return x / max(1e-9, np.abs(x).max())


def start_of(x, start, secs):
    """Where the stretch to print starts (sample). "auto": just before the loudest event's onset."""
    n = int(secs * SR)
    if start == "steady":   # (for a loop: the evenest stretch among the louder ones, 100 ms by 100 ms in dB)
        e = 10 * np.log10(np.convolve(x ** 2, np.ones(2205) / 2205, "same")[::2205] + 1e-10)
        k = max(1, n // 2205)
        best, bs = 0, 1e9
        med = np.median(e)
        for i in range(0, max(1, len(e) - k)):
            win = e[i:i + k]
            if win.mean() < med - 3:
                continue
            sc = win.std()
            if sc < bs:
                best, bs = i, sc
        return best * 2205
    if start.startswith("peak"):   # ("peak:-4": four seconds before the loudest moment)
        e = np.convolve(x ** 2, np.ones(4410) / 4410, "same")
        s = max(0, int(np.argmax(e) + float(start.split(":")[1]) * SR))
        return s
    if start.startswith("event"):   # ("event:2": the third loudest of its separate events, from just before its onset)
        e = np.convolve(x ** 2, np.ones(220) / 220, "same")
        order = np.argsort(-e)
        peaks = []
        for i in order[::37]:
            if all(abs(i - q) > 0.25 * SR for q in peaks):
                peaks.append(i)
            if len(peaks) > int(start.split(":")[1]) + 1:
                break
        peak = peaks[int(start.split(":")[1])]
        floor = e[peak] * 10 ** (-30 / 10)
        s = peak
        while s > 0 and e[s] > floor and peak - s < SR // 4:
            s -= 1
        s = max(0, s - int(0.005 * SR))
        return s
    if start != "auto":
        s = int(float(start) * SR)
        return s
    e = np.convolve(x ** 2, np.ones(220) / 220, "same")
    peak = int(np.argmax(e))
    floor = e[peak] * 10 ** (-30 / 10)
    s = peak
    while s > 0 and e[s] > floor and peak - s < SR // 2:
        s -= 1
    s = max(0, s - int(0.005 * SR))
    return s



def pick(x, start, secs):
    s = start_of(x, start, secs)
    return x[s:s + int(secs * SR)]


def cut_one_shot(x, s, secs, tail=True, fade=0.0):
    """A one-shot from s: secs long; longer only if it's dying away there (a ring, a tail: on until it's
    gone, down to the recording's own background or 45 dB under its peak for 50 ms, at most 2 s more, no
    further than the next thing starting up); then faded out smoothly, and a 3 ms fade in. (Cut at a
    fixed length, rings and tails stopped dead: an abrupt end.)"""
    n = int(secs * SR)
    hop = int(0.01 * SR)
    whole = 10 * np.log10(np.convolve(x ** 2, np.ones(2 * hop) / (2 * hop), "same")[::hop] + 1e-12)
    floor = np.percentile(whole, 10)   # (the recording's background, between its sounds)
    most = min(len(x), s + n + min(int(1.5 * n), 2 * SR))
    seg = x[s:most]
    e = whole[s // hop:most // hop]
    peak = int(np.argmax(e[:max(1, n // hop)]))
    top = e[peak]
    gone = max(top - 45, floor + 4)
    k0 = n // hop
    at_cut = float(np.mean(e[max(0, k0 - 3):k0 + 2])) if k0 < len(e) else -999.0
    end = k0
    if tail and gone < at_cut < top - 8:   # (dying away there, not yet gone: a ring, a tail. Steady ones just fade.)
        end = len(e)
        quiet = 0
        for k in range(k0, len(e)):
            if k >= 3 and e[k] - e[k - 3] > 12 and e[k] > top - 30:   # (something new starting: stop before it)
                end = k - 3
                break
            quiet = quiet + 1 if e[k] < gone else 0
            if quiet >= 5:
                end = k
                break
    m = min(len(seg), max(int(0.05 * SR), end * hop))
    y = seg[:m].copy()
    fl = min(int(fade * SR) if fade else int(np.clip(0.2 * m, 0.03 * SR, 0.35 * SR)), m // 2)
    y[-fl:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fl))
    fi = min(int(0.003 * SR), m // 4)
    y[:fi] *= np.linspace(0, 1, fi)
    return y

def tracks_of(x):
    """Sinusoids: spectral peaks well clear of the noise around them, joined frame to frame."""
    w = signal.get_window("hann", TN)
    nf = 1 + max(0, (len(x) - TN) // THOP)
    pad = np.concatenate([x, np.zeros(TN)])
    zp = 4 * TN
    live, done = [], []
    gtop = -999.0   # (the loudest peak anywhere: short tracks have to be near it)
    for f in range(nf):
        fr = pad[f * THOP:f * THOP + TN] * w
        mag = np.abs(np.fft.rfft(fr, zp)) / (w.sum() / 2)
        db = 20 * np.log10(mag + 1e-9)
        floor = ndimage.median_filter(db, 4 * 16 + 1, mode="nearest")
        top = db.max()
        gtop = max(gtop, top)
        cand = np.where((db[1:-1] > db[:-2]) & (db[1:-1] >= db[2:]) & (db[1:-1] > floor[1:-1] + 12) & (db[1:-1] > top - 60))[0] + 1
        pk = []
        for k in cand:
            a, b, c = db[k - 1], db[k], db[k + 1]
            p = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) != 0 else 0.0
            fz = (k + p) * SR / zp
            if 30 < fz < SR / 2 - 200:
                pk.append((b - 0.25 * (a - c) * p, fz))
        pk.sort(reverse=True)
        pk = pk[:40]
        used = set()
        nxt = []
        for t in sorted(live, key=lambda t: -t["a"][-1]):
            best, bd = None, None
            for i, (a, fz) in enumerate(pk):
                if i in used:
                    continue
                d = abs(fz - t["f"][-1])
                if d < max(0.04 * t["f"][-1], 25) and (bd is None or d < bd):
                    best, bd = i, d
            if best is None:   # (missed: held a few frames, fading, in case it's back)
                t["miss"] = t.get("miss", 0) + 1
                if t["miss"] > 3:
                    k = t["miss"] - 1
                    t["f"], t["a"] = t["f"][:-k], t["a"][:-k]
                    done.append(t)
                else:
                    t["f"].append(t["f"][-1])
                    t["a"].append(t["a"][-1] - 6.0)
                    nxt.append(t)
            else:
                used.add(best)
                t["miss"] = 0
                t["f"].append(pk[best][1])
                t["a"].append(pk[best][0])
                nxt.append(t)
        for i, (a, fz) in enumerate(pk):
            if i not in used:
                nxt.append({"s": f, "f": [fz], "a": [a]})
        live = nxt
    for t in live:
        k = t.get("miss", 0)
        if k:
            t["f"], t["a"] = t["f"][:-k], t["a"][:-k]
        done.append(t)
    # Short ones only if they're strong (a ring, a click's tone), not flecks of the noise.
    return [t for t in done if len(t["f"]) >= 32 or (len(t["f"]) >= 5 and max(t["a"]) > gtop - 20)]


def sines(tracks, n, rng):
    """The tonal part, as the game makes it: each track's frequency and level eased sample to sample."""
    y = np.zeros(n)
    for t in tracks:
        f = np.array(t["f"])
        a = 10 ** (np.array(t["a"]) / 20)
        a = np.concatenate([[0.0], a, [0.0]])   # (faded in and out over a hop)
        f = np.concatenate([[f[0]], f, [f[-1]]])
        s0 = (t["s"] - 1) * THOP + TN // 2
        idx = np.arange(len(f) - 1)
        span = np.arange(THOP) / THOP
        ff = (f[idx, None] + (f[idx + 1] - f[idx])[:, None] * span).ravel()
        aa = (a[idx, None] + (a[idx + 1] - a[idx])[:, None] * span).ravel()
        ph = rng.uniform(0, 2 * np.pi) + np.cumsum(2 * np.pi * ff / SR)
        seg = aa * np.sin(ph)
        lo = max(0, s0)
        hi = min(n, s0 + len(seg))
        if hi > lo:
            y[lo:hi] += seg[lo - s0:hi - s0]
    return y


def band_power(x):
    w = signal.get_window("hann", N)
    nf = 1 + max(0, (len(x) - N) // HOP) + 1
    pad = np.concatenate([np.zeros(N // 2), x, np.zeros(N)])
    out = np.zeros((nf, NB))
    for f in range(nf):
        p = np.abs(np.fft.rfft(pad[f * HOP:f * HOP + N] * w)) ** 2
        for b in range(NB):
            out[f, b] = p[EDGES[b]:EDGES[b + 1]].mean()
    return out


def fine_env(x):
    n = len(x) // ENV + 1
    p = np.concatenate([x, np.zeros(n * ENV - len(x))]).reshape(n, ENV)
    return np.sqrt((p ** 2).mean(axis=1))


# --- the rebuild (the game's algorithm) --------------------------------------------------------------

def noise(bands, env, n, rng):
    """The noise over SPLIT Hz: its 32 bands' spectrum; in each of the three ranges, its 2 ms envelope."""
    centers = [(EDGES[b] + EDGES[b + 1] - 1) / 2 for b in range(NB)]
    # (between band centres in dB, not in power: power blended straight overfills the quieter side;
    # on the doubled FFT's bins, each half a bin of the bands')
    parts = filtered(bands, n, rng, N, HOP, lambda row: 10 ** (np.interp(np.arange(N + 1) / 2.0, centers, np.log10(row)) / 2), masks(N + 1, SR))
    return sum(pull(y, env[j], ENV) for j, y in enumerate(parts))


def ranges(x):
    """x in the three ranges (the same crossfades, zero phase: they add back up to x)."""
    X = np.fft.rfft(x)
    return [np.fft.irfft(X * m, len(x)) for m in masks(len(X), SR)]


def split(x):
    """Under SPLIT Hz and the rest (zero phase, so the two add back up to x)."""
    bb, aa = signal.butter(4, SPLIT / (SR / 2), "low")
    lo = signal.filtfilt(bb, aa, x)
    return lo, x - lo


def low_power(x):
    w = signal.get_window("hann", NL)
    nf = 1 + max(0, (len(x) - NL) // HOPL) + 2
    pad = np.concatenate([np.zeros(NL // 2), x, np.zeros(2 * NL)])
    out = np.zeros((nf, LBINS))
    for f in range(nf):
        out[f] = (np.abs(np.fft.rfft(pad[f * HOPL:f * HOPL + NL] * w)) ** 2)[:LBINS]
    return out


def block_env(x, blk):
    n = len(x) // blk + 1
    p = np.concatenate([x, np.zeros(n * blk - len(x))]).reshape(n, blk)
    return np.sqrt((p ** 2).mean(axis=1))


def filtered(spec, n, rng, seg, hop, gain_of, parts=None):
    """White noise through a filter that changes frame by frame: each Hann-windowed stretch of seg samples
    (half overlapped: they add back up to the plain noise) filtered on its own, zero-padded to twice its
    length so the filtering doesn't wrap round, the results overlap-added. gain_of(frame) gives the gain on
    the 2*seg FFT's bins; parts (gains on those bins too), if given, splits it: one result per part.
    (Windowed only on the way in: a window on the way out too smeared the loud lows up into the quiet
    highs.) n samples each, frame f centred on sample f*hop."""
    w = signal.get_window("hann", seg, fftbins=True)
    nf = spec.shape[0]
    white = rng.standard_normal(nf * hop + seg)
    parts = parts if parts is not None else [1.0]
    ys = [np.zeros(nf * hop + 2 * seg) for _ in parts]
    buf = np.zeros(2 * seg)
    for f in range(nf):
        buf[:] = 0.0
        buf[seg // 2:seg // 2 + seg] = white[f * hop:f * hop + seg] * w
        sp = np.fft.rfft(buf) * gain_of(spec[f])
        for y, m in zip(ys, parts):
            y[f * hop:f * hop + 2 * seg] += np.fft.irfft(sp * m, 2 * seg)
    return [y[seg:seg + n] for y in ys]


def pull(y, env, blk):
    """Its loudness pulled onto env, block by block (against its own over three blocks, so the pull
    follows the recording, not the dice; no block pushed past the recording's own level)."""
    n = len(y)
    h2 = block_env(y, blk)
    have = np.maximum(np.sqrt(np.convolve(h2 ** 2, np.ones(3) / 3, "same")), h2)
    g = np.minimum(env[:len(have)] / np.maximum(have, 1e-12), 8.0)
    g = np.interp(np.arange(n), np.arange(len(g)) * blk + blk / 2, g)
    out = y * g
    # (that cap pulls it under the recording on the whole, the more the narrower the range: as loud in
    # all as the recording again)
    want = np.sum(env[:len(have)] ** 2) * blk
    return out * np.sqrt(want / max(1e-24, np.sum(out ** 2)))


DOWN = 8   # the low end is made at an eighth of the rate (the same 10.8 Hz bins: 256 points), then brought up


def up(z, n):
    """Back up to the full rate: linear steps, then a two-pole low-pass at 500 Hz (the images off)."""
    t = np.arange(n) / DOWN
    y = np.interp(t, np.arange(len(z)), z)
    w0 = 2 * np.pi * 500.0 / SR
    al = np.sin(w0) / (2 * 0.7071)
    b0 = (1 - np.cos(w0)) / 2
    bb = np.array([b0, 2 * b0, b0]) / (1 + al)
    aa = np.array([1.0, -2 * np.cos(w0) / (1 + al), (1 - al) / (1 + al)])
    return signal.lfilter(bb, aa, y)


def low_noise(low, envl, n, rng):
    nfl, hopl = NL // DOWN, HOPL // DOWN
    def bins_of(row):   # (each bin of the doubled FFT half a bin of the measured ones)
        m = np.zeros(nfl + 1)
        m[:2 * LBINS - 1] = np.sqrt(np.interp(np.arange(2 * LBINS - 1) / 2.0, np.arange(LBINS), row))
        return m
    z = filtered(low, n // DOWN + 2, rng, nfl, hopl, bins_of)[0]
    return pull(up(z, n), envl, ENVL)


def butter4(y, cut, kind):
    """A 4th-order Butterworth (two RBJ biquads, Q 0.5412 and 1.3066), forward only: the game's own."""
    for q in (0.5412, 1.3066):
        w0 = 2 * np.pi * cut / SR
        al = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        if kind == "lp":
            bb = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2])
        else:
            bb = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2])
        aa = np.array([1 + al, -2 * c, 1 - al])
        y = signal.lfilter(bb / aa[0], aa / aa[0], y)
    return y


def rebuild(pr, seed=1):
    rng = np.random.default_rng(seed)
    n = pr["n"]
    y = sines(pr["tracks"], n, rng) + noise(pr["bands"], pr["env"], n, rng)
    y += low_noise(pr["low"], pr["envl"], n, rng)
    for kind in ("lp", "hp"):   # (the recording was filtered so: the rebuild too, or the noise fills it back in)
        if pr.get(kind):
            y = butter4(y, pr[kind], kind)
    if pr.get("drive"):   # (squeezed here too: the rebuild's noise brings sharp peaks of its own back)
        g = 10 ** (pr["drive"] / 20)
        y = np.tanh(y / max(1e-9, np.abs(y).max()) * g) / np.tanh(g)
    return y * pr["gain"]


# --- packing (what the game reads) -------------------------------------------------------------------

def pack(pr):
    b = pr["bands"]
    bdb = 10 * np.log10(b + 1e-14)
    btop = bdb.max()
    bq = np.clip(np.round(btop - bdb), 0, 120).astype(np.uint8)   # 1 dB steps down from the loudest
    edb = 20 * np.log10(pr["env"] + 1e-9)   # (three ranges, one after another)
    etop = edb.max()
    eq = np.clip(np.round((etop - edb) * 2), 0, 240).astype(np.uint8)   # 0.5 dB steps
    tr = b""
    atop = max([max(t["a"]) for t in pr["tracks"]], default=0.0)
    for t in pr["tracks"]:
        tr += struct.pack("<HH", t["s"], len(t["f"]))
        tr += np.round(np.log2(np.array(t["f"]) / 20.0) * 4096).astype("<u2").tobytes()
        tr += np.clip(np.round((atop - np.array(t["a"])) * 2), 0, 255).astype(np.uint8).tobytes()
    ldb = 10 * np.log10(pr["low"] + 1e-14)
    ltop = ldb.max()
    lq = np.clip(np.round(ltop - ldb), 0, 120).astype(np.uint8)
    ledb = 20 * np.log10(pr["envl"] + 1e-9)
    letop = ledb.max()
    leq = np.clip(np.round((letop - ledb) * 2), 0, 240).astype(np.uint8)
    z = lambda raw: base64.b64encode(zlib.compress(raw, 9)).decode()
    return {"n": pr["n"], "loop": pr["loop"], "gain": round(pr["gain"], 5), "frames": int(b.shape[0]),
            "btop": round(float(btop), 2), "etop": round(float(etop), 2), "atop": round(float(atop), 2),
            "bands": z(bq.T.tobytes()), "env": z(eq.tobytes()), "tracks": z(tr),
            "lp": pr.get("lp", 0), "hp": pr.get("hp", 0), "drive": pr.get("drive", 0), "lframes": int(lq.shape[0]), "ltop": round(float(ltop), 2), "letop": round(float(letop), 2), "low": z(lq.T.tobytes()), "envl": z(leq.tobytes())}


def unpack(p):
    """Back from the packed numbers (so the rebuild here hears exactly what the game gets)."""
    u = lambda s: zlib.decompress(base64.b64decode(s))
    bq = np.frombuffer(u(p["bands"]), np.uint8).reshape(NB, p["frames"]).T
    bands = 10 ** ((p["btop"] - bq) / 10)
    env = 10 ** ((p["etop"] - np.frombuffer(u(p["env"]), np.uint8) / 2) / 20)
    env = env.reshape(3, -1)
    raw = u(p["tracks"])
    tracks, i = [], 0
    while i < len(raw):
        s, k = struct.unpack_from("<HH", raw, i)
        i += 4
        f = 20.0 * 2 ** (np.frombuffer(raw, "<u2", k, i) / 4096)
        i += 2 * k
        a = p["atop"] - np.frombuffer(raw, np.uint8, k, i) / 2
        i += k
        tracks.append({"s": s, "f": list(f), "a": list(a)})
    low = 10 ** ((p["ltop"] - np.frombuffer(u(p["low"]), np.uint8).reshape(LBINS, p["lframes"]).T) / 10)
    envl = 10 ** ((p["letop"] - np.frombuffer(u(p["envl"]), np.uint8) / 2) / 20)
    return {"n": p["n"], "loop": p["loop"], "gain": p["gain"], "bands": bands, "env": env, "tracks": tracks, "low": low, "envl": envl,
            "lp": p.get("lp", 0), "hp": p.get("hp", 0), "drive": p.get("drive", 0)}


def residual(x, tracks):
    """The recording with its tracked tones cut out: its spectrum, frame by frame, with the bins
    round each tone zeroed, put back together (its own phases kept, so its 2 ms envelope is real)."""
    w = signal.get_window("hann", TN)
    off = TN // THOP   # (padded a window in front: frame f of the tracks is frame f + off here)
    xp = np.concatenate([np.zeros(TN), x, np.zeros(2 * TN)])
    nf = (len(xp) - TN) // THOP + 1
    cut = {}
    for t in tracks:   # (a track's first and last frame reach back and on a window's width: cut there too)
        fs = [t["f"][0]] * off + list(t["f"]) + [t["f"][-1]] * off
        for j, fz in enumerate(fs):
            cut.setdefault(t["s"] + j, []).append(fz)
    y = np.zeros(len(xp))
    wsum = np.zeros(len(xp))
    for g in range(nf):
        fr = np.fft.rfft(xp[g * THOP:g * THOP + TN] * w)
        for fz in cut.get(g, []):
            k = int(round(fz / (SR / TN)))
            fr[max(0, k - 2):k + 3] = 0.0
        y[g * THOP:g * THOP + TN] += np.fft.irfft(fr, TN) * w
        wsum[g * THOP:g * THOP + TN] += w ** 2
    y = y / np.maximum(wsum, 1e-3)
    return y[TN:TN + len(x)]


def make_print(x, loop=False, match=None, lp=0, hp=0, drive=0):
    n = len(x)
    tr = tracks_of(x)
    r_lo, r_hi = split(residual(x, tr))
    resid = np.maximum(band_power(r_hi), 1e-14)
    floor = fine_env(x) * 1e-6
    env = np.array([np.maximum(fine_env(r), floor) for r in ranges(r_hi)])
    low = np.maximum(low_power(r_lo), 1e-14)
    envl = np.maximum(block_env(r_lo, ENVL), block_env(x, ENVL) * 0.001)
    pr = {"n": n, "loop": loop, "gain": 1.0, "tracks": tr, "bands": resid, "env": env, "low": low, "envl": envl, "lp": lp, "hp": hp, "drive": drive}
    y = rebuild(unpack(pack(pr)))
    if match is not None:   # as loud (RMS) as the sound it replaces, so the game's mix stays as it was
        pr["gain"] = float(np.sqrt(np.mean(match ** 2)) / max(1e-9, np.sqrt(np.mean(y ** 2))))
    else:
        pr["gain"] = 0.8 / max(1e-9, np.abs(y).max())
    # Never clipped, whatever the dice: the loudest peak over eight takes kept under full scale.
    worst = max(np.abs(rebuild(unpack(pack(pr)), seed)).max() / pr["gain"] for seed in range(2, 10 if n < 2 * SR else 5))
    pr["gain"] = min(pr["gain"], 0.88 / max(1e-9, worst))
    return pr


def loopify(y, xf):
    """A seamless loop: the last xf samples faded over the first."""
    head, tail = y[:xf], y[-xf:]
    k = np.linspace(0, 1, xf)
    out = y[:-xf].copy()
    out[:xf] = head * np.sqrt(k) + tail * np.sqrt(1 - k)
    return out


def spectro_distance(a, b):
    """How far apart two sounds are, band by band over time (dB, lower is closer)."""
    pa, pb = band_power(a), band_power(b)
    m = min(len(pa), len(pb))
    da = 10 * np.log10(pa[:m] + 1e-10)
    db = 10 * np.log10(pb[:m] + 1e-10)
    da -= da.max()
    db -= db.max()
    mask = (da > -50) | (db > -50)
    return float(np.mean(np.abs(np.clip(da, -60, 0) - np.clip(db, -60, 0))[mask]))


def main():
    a = sys.argv
    if a[1] == "search":
        for r in search(" ".join(a[2:]))[:15]:
            print("%7d %6.1fs %6d  %s (%s)" % (r["id"], r["secs"], r["downloads"], r["title"], r["user"]))
    elif a[1] == "searches":   # (a file of "name|query" lines, three at a time)
        from concurrent.futures import ThreadPoolExecutor
        qs = [l.strip().split("|", 1) for l in open(a[2]) if "|" in l]
        def one(q):
            try:
                rs = search(q[1])[:6]
            except Exception as e:
                return "== %s (%s): %s" % (q[0], q[1], e)
            return "\n".join(["== %s (%s)" % (q[0], q[1])] + ["%7d %6.1fs %6d  %s (%s)" % (r["id"], r["secs"], r["downloads"], r["title"], r["user"]) for r in rs])
        with ThreadPoolExecutor(3) as tx:
            for out in tx.map(one, qs):
                print(out)
    elif a[1] == "fetch":
        fetch(int(a[2]), a[3])
    elif a[1] == "bundle":
        src = json.load(open(a[3]))
        lines = ["# Sound prints: numbers measured from real recordings by tools/sound_print.py, rebuilt by",
                 "# sound_print.gd. Generated (python tools/sound_print.py bundle); the sources are in",
                 "# tools/sound_sources.json. Each sound: one print per take.", "extends RefCounted", "", "const P := {"]
        for name in sorted(src):
            takes = src[name] if isinstance(src[name], list) else [src[name]]
            files = [os.path.join(a[2], (name if len(takes) == 1 else "%s@%d" % (name, k)) + ".json") for k in range(len(takes))]
            if not all(os.path.exists(f) for f in files):
                continue
            for c in takes:
                lines.append('\t# %s: "%s" by %s (freesound %d, %s)' % (name, c["title"], c["user"], c["id"], c.get("license", "CC0")))
            lines.append('\t"%s": [%s],' % (name, ", ".join(json.dumps(json.load(open(f))) for f in files)))
        lines.append("}")
        open(a[4], "w").write("\n".join(lines) + "\n")
    elif a[1] == "build":   # (every take at once, one process a core)
        from concurrent.futures import ProcessPoolExecutor
        src = json.load(open(a[2]))
        jobs = []
        for name in (a[6:] or sorted(src)):
            takes = src[name] if isinstance(src[name], list) else [src[name]]
            for k, c in enumerate(takes):
                jobs.append((name if len(takes) == 1 else "%s@%d" % (name, k), c, os.path.join(a[3], "%d.wav" % c["id"]), a[4], os.path.join(a[5], name + ".wav")))
        from concurrent.futures import ThreadPoolExecutor
        missing = sorted({j[2] for j in jobs if not os.path.exists(j[2])})
        with ThreadPoolExecutor(3) as tx:   # (fetched first, three at a time: one at a time took most of a batch)
            list(tx.map(lambda ref: fetch(int(os.path.basename(ref)[:-4]), ref), missing))
        with ProcessPoolExecutor() as ex:
            for line in ex.map(build_one, jobs):
                print(line, flush=True)
    elif a[1] == "print":
        wav, start, secs, name, out = a[2], a[3], float(a[4]), a[5], a[6]
        loop = "loop" in a[7:]
        mt = [v for v in a[7:] if v.endswith(".wav")]
        x = pick(load(wav), start, secs)
        match = None
        if mt:
            r, m = wavfile.read(mt[0])
            match = m.astype(np.float64) / (32768.0 if m.dtype == np.int16 else 1.0)
        report(x, name, out, loop, match)


def build_one(job):
    name, c, ref, out, old = job
    match = None   # (as loud as the recording lets it be, not the old synth: matched to the old, they came out quiet)
    x = load(ref)
    if "hp" in c:   # (just the part over this: a whistle off an engine)
        x = signal.sosfiltfilt(signal.butter(4, c["hp"] / (SR / 2), "high", output="sos"), x)
    if "lp" in c:   # (just the part under it: heard from far off)
        x = signal.sosfiltfilt(signal.butter(4, c["lp"] / (SR / 2), "low", output="sos"), x)
    x = x / max(1e-9, np.abs(x).max())
    s0 = start_of(x, c["start"], c["secs"])
    x = x[s0:s0 + int(c["secs"] * SR)] if c.get("loop") else cut_one_shot(x, s0, c["secs"], c.get("tail", True), c.get("fade", 0.0))
    if c.get("drive"):   # (louder than its peaks allow: the peaks squeezed, a soft limit, so the body comes up)
        g = 10 ** (c["drive"] / 20)
        x = np.tanh(x / max(1e-9, np.abs(x).max()) * g) / np.tanh(g)
    return report(x / max(1e-9, np.abs(x).max()), name, out, c.get("loop", False), match, quiet=True, lp=c.get("lp", 0), hp=c.get("hp", 0), drive=c.get("drive", 0))


def report(x, name, out, loop, match, quiet=False, lp=0, hp=0, drive=0):
    pr = make_print(x, loop, match, lp, hp, drive)
    p = pack(pr)
    os.makedirs(out, exist_ok=True)
    json.dump(p, open(os.path.join(out, name + ".json"), "w"))
    y = rebuild(unpack(p))
    if loop:
        y = loopify(y, SR // 4)
    wavfile.write(os.path.join(out, name + "_rebuild.wav"), SR, (np.clip(y, -1, 1) * 32000).astype(np.int16))
    wavfile.write(os.path.join(out, name + "_source.wav"), SR, (x * 32000).astype(np.int16))
    line = json.dumps({"name": name, "secs": round(len(x) / SR, 2), "tracks": len(pr["tracks"]), "bytes": sum(len(p[k]) for k in ("bands", "env", "tracks", "low", "envl")),
                       "distance_db": round(spectro_distance(x, y[:len(x)] / p["gain"]), 2)})
    if quiet:
        return line
    print(line)


if __name__ == "__main__":
    import urllib.parse
    main()
