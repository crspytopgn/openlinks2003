class_name Bunky
extends RefCounted
## The block cipher that locks course archives. A GDScript port of
## libs/olcore/src/bunky.cpp; change both together. See docs/formats/crz.md.
##
## The tables come from the player's own game executable (CrzArchive.find_keys)
## and are never shipped with this project.

const P_WORDS := 32
const S_WORDS := 1022
const MASK32 := 0xFFFFFFFF

var _p := PackedInt64Array()
var _s := PackedInt64Array()
var _rounds := 4


## `tables` holds the 32 P words followed by the 1022 S words.
func _init(tables: PackedInt64Array, key: PackedByteArray, rounds: int) -> void:
	assert(tables.size() == P_WORDS + S_WORDS and not key.is_empty())
	_rounds = clampi(rounds, 4, 32)
	var key_len := mini(key.size(), 7)
	_p = tables.slice(0, P_WORDS)
	_s = tables.slice(P_WORDS, P_WORDS + S_WORDS)
	for i in P_WORDS:
		var k := 0
		for j in 4:
			k = (k << 8) | key[(4 * i + j) % key_len]
		_p[i] = _p[i] ^ k
	# Encrypt both tables in place with the cipher itself. Every write goes
	# straight back to the table, because later steps of the same block may
	# look it up.
	_chain_encrypt_table(true, P_WORDS >> 1)
	_chain_encrypt_table(false, S_WORDS >> 1)


func _sv(v: int, r: int) -> int:
	return _s[((v + r) & MASK32) % S_WORDS]


## Encrypts the block held in words w0 (bytes 0-3) and w1 (bytes 4-7).
## When `table` is not 0, the block is table words idx and idx + 1 (1 = P,
## 2 = S) and each step is written back before the next lookup.
func _encrypt_words(w0: int, w1: int, table: int, idx: int) -> int:
	for r in _rounds:
		# front ^= S(back + r) ^ P[r]
		w0 ^= _sv(w1, r) ^ _p[r & 31]
		if table != 0:
			_store(table, idx, w0, w1)
		# outer (h0 high, h3 low) ^= S(middle + r) ^ P[r + 8]
		var middle := (w0 >> 16) | ((w1 & 0xFFFF) << 16)
		var x := _sv(middle, r) ^ _p[(r + 8) & 31]
		w0 = (w0 & 0xFFFF0000) | ((w0 & 0xFFFF) ^ (x >> 16))
		w1 = (w1 & 0x0000FFFF) | (((w1 >> 16) ^ (x & 0xFFFF)) << 16)
		if table != 0:
			_store(table, idx, w0, w1)
		# middle ^= S(outer + r) ^ P[r + 16]
		var outer := ((w0 & 0xFFFF) << 16) | (w1 >> 16)
		x = _sv(outer, r) ^ _p[(r + 16) & 31]
		w0 = (w0 & 0x0000FFFF) | ((((w0 >> 16) ^ x) & 0xFFFF) << 16)
		w1 = (w1 & 0xFFFF0000) | ((w1 ^ (x >> 16)) & 0xFFFF)
		if table != 0:
			_store(table, idx, w0, w1)
		# back ^= S(front + r) ^ P[r + 24]
		w1 ^= _sv(w0, r) ^ _p[(r + 24) & 31]
		if table != 0:
			_store(table, idx, w0, w1)
	return _pack(w0, w1)


func _decrypt_words(w0: int, w1: int) -> int:
	for r in range(_rounds - 1, -1, -1):
		w1 ^= _sv(w0, r) ^ _p[(r + 24) & 31]
		var outer := ((w0 & 0xFFFF) << 16) | (w1 >> 16)
		var x := _sv(outer, r) ^ _p[(r + 16) & 31]
		w0 = (w0 & 0x0000FFFF) | ((((w0 >> 16) ^ x) & 0xFFFF) << 16)
		w1 = (w1 & 0xFFFF0000) | ((w1 ^ (x >> 16)) & 0xFFFF)
		var middle := (w0 >> 16) | ((w1 & 0xFFFF) << 16)
		x = _sv(middle, r) ^ _p[(r + 8) & 31]
		w0 = (w0 & 0xFFFF0000) | ((w0 & 0xFFFF) ^ (x >> 16))
		w1 = (w1 & 0x0000FFFF) | (((w1 >> 16) ^ (x & 0xFFFF)) << 16)
		w0 ^= _sv(w1, r) ^ _p[r & 31]
	return _pack(w0, w1)


## Both words in one int: w0 low, w1 high.
static func _pack(w0: int, w1: int) -> int:
	return (w1 << 32) | w0


static func _lo(v: int) -> int:
	return v & MASK32


static func _hi(v: int) -> int:
	return (v >> 32) & MASK32


func _store(table: int, idx: int, w0: int, w1: int) -> void:
	if table == 1:
		_p[idx] = w0
		_p[idx + 1] = w1
	else:
		_s[idx] = w0
		_s[idx + 1] = w1


# Propagating CBC over a table: each block is XORed with the previous
# plaintext and ciphertext blocks before it is encrypted. No IV.
func _chain_encrypt_table(is_p: bool, blocks: int) -> void:
	var table := 1 if is_p else 2
	var pp0 := 0
	var pp1 := 0
	var pc0 := 0
	var pc1 := 0
	for i in blocks:
		var idx := 2 * i
		var w0: int = _p[idx] if is_p else _s[idx]
		var w1: int = _p[idx + 1] if is_p else _s[idx + 1]
		var plain0 := w0
		var plain1 := w1
		if i > 0:
			w0 = plain0 ^ pp0 ^ pc0
			w1 = plain1 ^ pp1 ^ pc1
			_store(table, idx, w0, w1)
		var c := _encrypt_words(w0, w1, table, idx)
		pp0 = plain0
		pp1 = plain1
		pc0 = _lo(c)
		pc1 = _hi(c)


func _bytes_mode(data: PackedByteArray, encrypting: bool) -> void:
	var n := data.size()
	if n == 1:
		data[0] = data[0] ^ ((_s[0] ^ _p[0]) & 0xFF)
		return
	for pass_index in 32:
		var k := pass_index if encrypting else 31 - pass_index
		for step in n:
			var j := step if encrypting else n - 1 - step
			data[j] = (_sv(data[(j + 1) % n], j) ^ data[j] ^ _p[k]) & 0xFF


## Returns an encrypted copy of `data`.
func encrypt(data: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	var n := out.size()
	if n == 0:
		return out
	if n < 8:
		_bytes_mode(out, true)
		return out
	# The last 8 bytes first, so a length that is not a multiple of 8 is still
	# fully covered; then the chain over the whole blocks.
	var t := _encrypt_words(out.decode_u32(n - 8), out.decode_u32(n - 4), 0, 0)
	out.encode_u32(n - 8, _lo(t))
	out.encode_u32(n - 4, _hi(t))
	if n > 8:
		var pp0 := 0
		var pp1 := 0
		var pc0 := 0
		var pc1 := 0
		for i in n >> 3:
			var o := 8 * i
			var plain0 := out.decode_u32(o)
			var plain1 := out.decode_u32(o + 4)
			var w0 := plain0
			var w1 := plain1
			if i > 0:
				w0 = plain0 ^ pp0 ^ pc0
				w1 = plain1 ^ pp1 ^ pc1
			var c := _encrypt_words(w0, w1, 0, 0)
			out.encode_u32(o, _lo(c))
			out.encode_u32(o + 4, _hi(c))
			pp0 = plain0
			pp1 = plain1
			pc0 = _lo(c)
			pc1 = _hi(c)
	return out


## Returns a decrypted copy of `data`.
func decrypt(data: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	var n := out.size()
	if n == 0:
		return out
	if n < 8:
		_bytes_mode(out, false)
		return out
	if n > 8:
		var pp0 := 0
		var pp1 := 0
		var pc0 := 0
		var pc1 := 0
		for i in n >> 3:
			var o := 8 * i
			var c0 := out.decode_u32(o)
			var c1 := out.decode_u32(o + 4)
			var p := _decrypt_words(c0, c1)
			var w0 := _lo(p)
			var w1 := _hi(p)
			if i > 0:
				w0 = w0 ^ pp0 ^ pc0
				w1 = w1 ^ pp1 ^ pc1
			out.encode_u32(o, w0)
			out.encode_u32(o + 4, w1)
			pp0 = w0
			pp1 = w1
			pc0 = c0
			pc1 = c1
	var t := _decrypt_words(out.decode_u32(n - 8), out.decode_u32(n - 4))
	out.encode_u32(n - 8, _lo(t))
	out.encode_u32(n - 4, _hi(t))
	return out
