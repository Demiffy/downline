# A sound rebuilt from its "sound print": numbers measured from a real recording by
# tools/sound_print.py (the recording itself isn't shipped; sound_prints.gd holds the numbers).
#   tracks      the tonal part: sinusoids, each one's frequency and level through time
#   bands, env  the noise over 350 Hz: its level in 32 bands 86 times a second, its loudness every 2 ms
#               in each of three ranges (to 1.5 kHz, to 5 kHz, over)
#   low, envl   the noise under it: finer in pitch (11 Hz bins, so a thud's own rings), every 6 ms
#               (made at an eighth of the rate: all it holds is under 430 Hz)
# The same algorithm as the tool's rebuild, so what it writes to hear is what plays here.
extends RefCounted

const VERSION := 4   # (bump when the rebuild changes: the cache of built sounds starts over)
const SR := 22050
const N := 512
const HOP := 256
const NB := 32
const TN := 1024
const THOP := 128
const ENV := 44
const NL := 2048
const HOPL := 512
const LBINS := 40
const ENVL := 132
const DOWN := 8   # the low end is made at an eighth of the rate (the same 10.8 Hz bins: 256 points), then brought up
const EDGES := [0, 2, 3, 4, 5, 6, 7, 9, 11, 13, 15, 17, 20, 23, 27, 31, 35, 40, 46, 52, 59, 67, 76, 86, 97, 110, 124, 140, 159, 179, 202, 227, 257]   # (tools/sound_print.py edges(): the same)

static var _tables := {}   # FFT size -> [cos, sin, bit reversal, Hann window of half the size]
static var _bin_band := PackedInt32Array()   # each bin of the doubled FFT: the band centre below it
static var _bin_frac := PackedFloat64Array() # and how far on to the next
static var _masks := []   # the three ranges' crossfades over the doubled FFT's bins (they add up to 1)
const EB := [1500.0, 5000.0]


static func _setup() -> void:
	if not _tables.is_empty():
		return
	for size in [2 * N, 2 * NL / DOWN]:   # (each stretch zero-padded to twice its length: the filtering doesn't wrap)
		var c := PackedFloat64Array()
		var sn := PackedFloat64Array()
		c.resize(size / 2)
		sn.resize(size / 2)
		for k in size / 2:
			c[k] = cos(TAU * k / size)
			sn[k] = sin(TAU * k / size)
		var rev := PackedInt32Array()
		rev.resize(size)
		var bits := int(round(log(size) / log(2.0)))
		for i in size:
			var r := 0
			for b in bits:
				if i & (1 << b):
					r |= 1 << (bits - 1 - b)
			rev[i] = r
		var win := PackedFloat64Array()
		win.resize(size / 2)
		for i in size / 2:   # (on the way in only)
			win[i] = 0.5 - 0.5 * cos(TAU * i / (size / 2))
		_tables[size] = [c, sn, rev, win]
	var centers := []
	for b in NB:
		centers.append((EDGES[b] + EDGES[b + 1] - 1) / 2.0)
	_bin_band.resize(N + 1)
	_bin_frac.resize(N + 1)
	for k2 in N + 1:   # (as numpy.interp: held flat past the first and last centre; bin k2 is half a bin of theirs)
		var k := k2 / 2.0
		var b := 0
		while b < NB - 1 and centers[b + 1] <= k:
			b += 1
		if k <= centers[0]:
			_bin_band[k2] = 0
			_bin_frac[k2] = 0.0
		elif b >= NB - 1:
			_bin_band[k2] = NB - 2
			_bin_frac[k2] = 1.0
		else:
			_bin_band[k2] = b
			_bin_frac[k2] = (k - centers[b]) / (centers[b + 1] - centers[b])
	var rise := func(e: float) -> PackedFloat64Array:   # 0 below e/1.25, 1 over e*1.25, a raised cosine between (log frequency)
		var r := PackedFloat64Array()
		r.resize(N + 1)
		for k in N + 1:
			var f := k * SR / (2.0 * N)
			var t := clampf((log(maxf(f, 1.0)) - log(e / 1.25)) / (log(e * 1.25) - log(e / 1.25)), 0.0, 1.0)
			r[k] = 0.5 - 0.5 * cos(PI * t)
		return r
	var r1: PackedFloat64Array = rise.call(EB[0])
	var r2: PackedFloat64Array = rise.call(EB[1])
	var m0 := PackedFloat64Array()
	var m1 := PackedFloat64Array()
	m0.resize(N + 1)
	m1.resize(N + 1)
	for k in N + 1:
		m0[k] = 1.0 - r1[k]
		m1[k] = r1[k] - r2[k]
	_masks = [m0, m1, r2]


static func _unz(s: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(s).decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)


## The sound, from its print (rng: this take's dice).
static func build(p: Dictionary, rng: RandomNumberGenerator) -> PackedFloat32Array:
	_setup()
	var n: int = p.n
	var y := PackedFloat32Array()
	y.resize(n)
	_sines(p, y, rng)
	# The noise over 350 Hz: 32 bands, spread across the bins between their centres.
	var frames: int = p.frames
	var bq := _unz(p.bands)
	var btop: float = p.btop
	var hi := func(f: int, gain: PackedFloat64Array) -> void:
		var mag := PackedFloat64Array()
		mag.resize(NB)
		for b in NB:   # (in dB, blended between band centres in dB: power blended straight overfills the quieter side)
			mag[b] = btop - bq[b * frames + f]
		for k in N + 1:
			var bb := _bin_band[k]
			gain[k] = pow(10.0, lerpf(mag[bb], mag[bb + 1], _bin_frac[k]) / 20.0)
	var parts := _filtered(frames, hi, rng, N, HOP, n, _masks)
	var eq := _unz(p.env)
	var per := eq.size() / 3
	for j in 3:   # (each range its own envelope: one for all let the loud lows' swings pump the quiet highs)
		_pull(y, parts[j], eq.slice(j * per, (j + 1) * per), p.etop, ENV)
	# Under it: bin by bin, at an eighth of the rate, then up to the full rate.
	if p.has("low"):
		var lframes: int = p.lframes
		var lq := _unz(p.low)
		var ltop: float = p.ltop
		var lo := func(f: int, gain: PackedFloat64Array) -> void:
			gain.fill(0.0)
			for k in 2 * LBINS - 1:   # (each bin of the doubled FFT half a bin of the measured ones)
				var k0 := k / 2
				var pw := pow(10.0, (ltop - lq[k0 * lframes + f]) / 10.0)
				if k % 2 == 1:
					pw = (pw + pow(10.0, (ltop - lq[(k0 + 1) * lframes + f]) / 10.0)) / 2.0
				gain[k] = sqrt(pw)
		var z: PackedFloat64Array = _filtered(lframes, lo, rng, NL / DOWN, HOPL / DOWN, n / DOWN + 2, [null])[0]
		_pull(y, _up(z, n), _unz(p.envl), p.letop, ENVL)
	for kind in ["lp", "hp"]:   # (the recording was filtered so: the rebuild too, or the noise fills it back in)
		if float(p.get(kind, 0)) > 0.0:
			_butter4(y, float(p[kind]), kind)
	if float(p.get("drive", 0)) > 0.0:   # (squeezed: the rebuild's noise brings sharp peaks of its own back)
		var dg := pow(10.0, float(p.drive) / 20.0)
		var pk := 0.0
		for i in n:
			pk = maxf(pk, absf(y[i]))
		var norm := tanh(dg)
		for i in n:
			y[i] = tanh(y[i] / maxf(pk, 1e-9) * dg) / norm
	var g: float = p.gain
	for i in n:
		y[i] *= g
	if p.loop:   # the last quarter second faded over the first: round and round without a seam
		var xf := SR / 4
		var out := y.slice(0, n - xf)
		for i in xf:
			var k := float(i) / (xf - 1)
			out[i] = y[i] * sqrt(k) + y[n - xf + i] * sqrt(1.0 - k)
		return out
	return y


static func _sines(p: Dictionary, y: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var raw := _unz(p.tracks)
	var atop: float = p.atop
	var n := y.size()
	var i := 0
	while i < raw.size():
		var s := raw.decode_u16(i)
		var k := raw.decode_u16(i + 2)
		i += 4
		var f := PackedFloat64Array()
		var a := PackedFloat64Array()
		f.resize(k + 2)
		a.resize(k + 2)
		for j in k:
			f[j + 1] = 20.0 * pow(2.0, raw.decode_u16(i + 2 * j) / 4096.0)
			a[j + 1] = pow(10.0, (atop - raw[i + 2 * k + j] / 2.0) / 20.0)
		i += 3 * k
		f[0] = f[1]
		f[k + 1] = f[k]
		a[0] = 0.0
		a[k + 1] = 0.0
		var s0 := (s - 1) * THOP + TN / 2
		var ph := rng.randf() * TAU
		for seg in k + 1:
			var at := s0 + seg * THOP
			if at >= n:
				break
			var f0 := f[seg]
			var df := (f[seg + 1] - f0) / THOP
			var a0 := a[seg]
			var da := (a[seg + 1] - a0) / THOP
			for q in THOP:
				ph += TAU * (f0 + df * q) / SR
				var o := at + q
				if o >= 0 and o < n:
					y[o] += (a0 + da * q) * sin(ph)


## White noise through a filter that changes frame by frame: each Hann-windowed stretch of seg samples
## (half overlapped: they add back up to the plain noise) filtered on its own, zero-padded to twice its
## length so the filtering doesn't wrap round, overlap-added. gain_of(frame, gains) fills the gain on the
## doubled FFT's bins; parts (gains on those bins too, null for all of it) split it, one result each.
## (Windowed only on the way in: a window on the way out too smeared the loud lows up into the quiet
## highs.) n samples each, frame f centred on sample f*hop.
static func _filtered(frames: int, gain_of: Callable, rng: RandomNumberGenerator, seg: int, hop: int, n: int, parts: Array) -> Array:
	var size := 2 * seg
	var win: PackedFloat64Array = _tables[size][3]
	var white := PackedFloat64Array()
	white.resize(frames * hop + seg)
	for i in white.size():
		white[i] = rng.randfn(0.0, 1.0)
	var outs := []
	for q in parts:
		var o := PackedFloat64Array()
		o.resize(frames * hop + size)
		outs.append(o)
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(size)
	im.resize(size)
	var sre := PackedFloat64Array()
	var sim := PackedFloat64Array()
	sre.resize(size / 2 + 1)
	sim.resize(size / 2 + 1)
	var gain := PackedFloat64Array()
	gain.resize(size / 2 + 1)
	for f in frames:
		gain_of.call(f, gain)
		var at := f * hop
		re.fill(0.0)
		im.fill(0.0)
		for t in seg:
			re[seg / 2 + t] = white[at + t] * win[t]
		_fft(re, im, false)
		for k in size / 2 + 1:
			sre[k] = re[k] * gain[k]
			sim[k] = im[k] * gain[k]
		var pi := 0
		while pi < parts.size():   # (two parts at a time: two real results ride one inverse FFT, a + i*b)
			var ma = parts[pi]
			var mb = parts[pi + 1] if pi + 1 < parts.size() else null
			var two := pi + 1 < parts.size()
			for k in size / 2 + 1:
				var ka: float = 1.0 if ma == null else ma[k]
				var ar := sre[k] * ka
				var ai := sim[k] * ka
				if k == 0 or k == size / 2:
					ai = 0.0
				var br := 0.0
				var bi := 0.0
				if two:
					var kb: float = 1.0 if mb == null else mb[k]
					br = sre[k] * kb
					bi = 0.0 if k == 0 or k == size / 2 else sim[k] * kb
				re[k] = ar - bi
				im[k] = ai + br
				if k > 0 and k < size / 2:   # (the mirrored bin: conj(A) + i*conj(B))
					re[size - k] = ar + bi
					im[size - k] = -ai + br
			_fft(re, im, true)
			var oa: PackedFloat64Array = outs[pi]
			for t in size:
				oa[at + t] += re[t]
			if two:
				var ob: PackedFloat64Array = outs[pi + 1]
				for t in size:
					ob[at + t] += im[t]
			pi += 2
	var res := []
	for o in outs:
		res.append(o.slice(seg, seg + n))
	return res


## The low end back up to the full rate: linear steps, then a two-pole low-pass at 500 Hz (the images off).
static func _up(z: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var w0 := TAU * 500.0 / SR
	var al := sin(w0) / (2.0 * 0.7071)
	var b0 := (1.0 - cos(w0)) / 2.0 / (1.0 + al)
	var a1 := -2.0 * cos(w0) / (1.0 + al)
	var a2 := (1.0 - al) / (1.0 + al)
	var y := PackedFloat64Array()
	y.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var last := z.size() - 1
	for i in n:
		var t := float(i) / DOWN
		var k := mini(int(t), last)
		var x := z[k] if k >= last else lerpf(z[k], z[k + 1], t - k)
		var o := b0 * x + 2.0 * b0 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = o
		y[i] = o
	return y


## nz's loudness pulled onto the measured envelope, block by block (against its own over three blocks,
## so the pull follows the recording, not the dice; no block pushed past the recording's own level),
## and added into y.
static func _pull(y: PackedFloat32Array, nz: PackedFloat64Array, eq: PackedByteArray, etop: float, blk: int) -> void:
	var n := y.size()
	var blocks := n / blk + 1
	var h2 := PackedFloat64Array()
	h2.resize(blocks)
	for bl in blocks:
		var acc := 0.0
		for t in blk:
			var o := bl * blk + t
			var v := nz[o] if o < n else 0.0
			acc += v * v
		h2[bl] = acc / blk
	var g := PackedFloat64Array()
	g.resize(blocks)
	for bl in blocks:
		var have := sqrt(maxf(((h2[bl - 1] if bl > 0 else 0.0) + h2[bl] + (h2[bl + 1] if bl < blocks - 1 else 0.0)) / 3.0, h2[bl]))
		var want := pow(10.0, (etop - (eq[bl] if bl < eq.size() else 240) / 2.0) / 20.0)
		g[bl] = minf(want / maxf(have, 1e-12), 8.0)
	var total := 0.0
	for bl in blocks:
		var e := pow(10.0, (etop - (eq[bl] if bl < eq.size() else 240) / 2.0) / 20.0)
		total += e * e * blk
	var out := PackedFloat64Array()
	out.resize(n)
	var got := 0.0
	for i in n:   # (as numpy.interp, between block centres)
		var pos := (i - blk / 2.0) / blk
		var k0 := clampi(int(floor(pos)), 0, blocks - 1)
		var k1 := mini(k0 + 1, blocks - 1)
		var gi := g[0] if pos <= 0.0 else lerpf(g[k0], g[k1], pos - floor(pos))
		out[i] = nz[i] * gi
		got += out[i] * out[i]
	# (that cap pulls it under the recording on the whole, the more the narrower the range: as loud in all
	# as the recording again)
	var k := sqrt(total / maxf(got, 1e-24))
	for i in n:
		y[i] += out[i] * k


## A 4th-order Butterworth in place (two RBJ biquads, Q 0.5412 and 1.3066), forward only.
static func _butter4(y: PackedFloat32Array, cut: float, kind: String) -> void:
	for q: float in [0.5412, 1.3066]:
		var w0 := TAU * cut / SR
		var al := sin(w0) / (2.0 * q)
		var c := cos(w0)
		var a0 := 1.0 + al
		var b0 := ((1.0 - c) / 2.0 if kind == "lp" else (1.0 + c) / 2.0) / a0
		var b1 := ((1.0 - c) if kind == "lp" else -(1.0 + c)) / a0
		var b2 := b0
		var a1 := -2.0 * c / a0
		var a2 := (1.0 - al) / a0
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in y.size():
			var x := float(y[i])
			var o := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
			x2 = x1
			x1 = x
			y2 = y1
			y1 = o
			y[i] = o


## In place, radix 2, any size set up in _tables (inverse: with the 1/size).
static func _fft(re: PackedFloat64Array, im: PackedFloat64Array, inverse: bool) -> void:
	var size := re.size()
	var tb: Array = _tables[size]
	var cs: PackedFloat64Array = tb[0]
	var sn: PackedFloat64Array = tb[1]
	var rev: PackedInt32Array = tb[2]
	var sg := 1.0 if inverse else -1.0
	for i in size:
		var j := rev[i]
		if j > i:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var span := 2
	while span <= size:
		var hs := span / 2
		var step := size / span
		var st := 0
		while st < size:
			for k in hs:
				var wr := cs[k * step]
				var wi := sg * sn[k * step]
				var a := st + k
				var b := a + hs
				var tr := re[b] * wr - im[b] * wi
				var ti := re[b] * wi + im[b] * wr
				re[b] = re[a] - tr
				im[b] = im[a] - ti
				re[a] += tr
				im[a] += ti
			st += span
		span *= 2
	if inverse:
		for i in size:
			re[i] /= size
