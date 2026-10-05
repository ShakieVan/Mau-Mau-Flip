class_name NetWs
extends RefCounted

# WebSocket nach RFC 6455, nur das, was der eigene Server braucht: Handshake-Schlüssel (SHA-1 + Base64), Rahmen kodieren (Server
# unmaskiert, für Tests auch maskiert wie ein Browser) und Rahmen zerlegen (Maskierung, 7/16/64-Bit-Längen, Prüfungen).
# Rein und zustandslos – der Server ruft es aus seinem Netz-Thread auf.

const GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const OP_CONT := 0
const OP_TEXT := 1
const OP_BINARY := 2
const OP_CLOSE := 8
const OP_PING := 9
const OP_PONG := 10
const MAX_CONTROL := 125
# Schließcodes
const CLOSE_NORMAL := 1000
const CLOSE_GOING_AWAY := 1001
const CLOSE_PROTOCOL := 1002
const CLOSE_UNSUPPORTED := 1003
const CLOSE_NO_STATUS := 1005
const CLOSE_INVALID_DATA := 1007
const CLOSE_POLICY := 1008
const CLOSE_TOO_BIG := 1009
const CLOSE_INTERNAL := 1011
const CLOSE_REPLACED := 4000              # eigene Codes 4000–4999: neue Verbindung desselben Spielers
const CLOSE_TIMEOUT := 4001               # Anmeldung oder Lebenszeichen ausgeblieben

static func accept_key(key: String) -> String:
	# Sec-WebSocket-Accept = Base64(SHA-1(Schlüssel + GUID)).
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update((key.strip_edges() + GUID).to_ascii_buffer())
	return Marshalls.raw_to_base64(ctx.finish())

static func valid_key(key: String) -> bool:
	# Der Schlüssel ist Base64 von 16 Zufallsbytes (24 Zeichen).
	var k := key.strip_edges()
	return k.length() == 24 and Marshalls.base64_to_raw(k).size() == 16

static func encode_frame(opcode: int, payload: PackedByteArray, fin := true, mask := false, mask_key := PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray()
	out.append((0x80 if fin else 0) | (opcode & 0x0F))
	var n := payload.size()
	var mbit := 0x80 if mask else 0
	if n < 126:
		out.append(mbit | n)
	elif n < 65536:
		out.append(mbit | 126)
		out.append((n >> 8) & 255)
		out.append(n & 255)
	else:
		out.append(mbit | 127)
		for i in range(7, -1, -1):
			out.append((n >> (8 * i)) & 255)
	if mask:
		var key := mask_key if mask_key.size() == 4 else Crypto.new().generate_random_bytes(4)
		out.append_array(key)
		out.append_array(apply_mask(payload, key))
	else:
		out.append_array(payload)
	return out

static func text_frame(text: String) -> PackedByteArray:
	return encode_frame(OP_TEXT, text.to_utf8_buffer())

static func close_frame(code: int, reason := "", mask := false) -> PackedByteArray:
	return encode_frame(OP_CLOSE, close_payload(code, reason), true, mask)

static func close_payload(code: int, reason := "") -> PackedByteArray:
	if code <= 0:
		return PackedByteArray()
	var out := PackedByteArray([(code >> 8) & 255, code & 255])
	var r := reason.to_utf8_buffer()
	if r.size() > MAX_CONTROL - 2:
		r = reason.left(40).to_utf8_buffer()
	out.append_array(r)
	return out

static func parse_close(payload: PackedByteArray) -> Array:
	# [Code, Grund]; ohne Code: [1005, ""]
	if payload.size() < 2:
		return [CLOSE_NO_STATUS, ""]
	return [(payload[0] << 8) | payload[1], payload.slice(2).get_string_from_utf8() if payload.size() > 2 and valid_utf8(payload.slice(2)) else ""]

static func valid_close_code(code: int) -> bool:
	# Codes, die ein Client senden darf (RFC 6455 7.4).
	return (code >= 1000 and code <= 1003) or (code >= 1007 and code <= 1011) or (code >= 3000 and code <= 4999)

static func apply_mask(data: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	# XOR mit dem 4-Byte-Schlüssel, je 4 Byte auf einmal (Ganzzahlen statt Einzelbytes).
	var n := data.size()
	if n == 0:
		return PackedByteArray()
	var padded := data.duplicate()
	var pad := (4 - n % 4) % 4
	if pad > 0:
		padded.resize(n + pad)
	var words := padded.to_int32_array()
	var k := key.to_int32_array()[0]
	for i in range(words.size()):
		words[i] = words[i] ^ k
	var out := words.to_byte_array()
	if pad > 0:
		out.resize(n)
	return out

static func parse_frame(buf: PackedByteArray, offset: int, max_payload: int) -> Dictionary:
	# Einen Rahmen ab offset zerlegen. Ergebnis:
	#   {status: "need"}                                   – noch nicht vollständig
	#   {status: "error", code, reason}                    – Protokollfehler (Verbindung mit code schließen)
	#   {status: "ok", fin, opcode, masked, payload, size} – size = verbrauchte Byte
	# max_payload begrenzt die Nutzlast eines Rahmens (größer → 1009 ohne auf die Daten zu warten).
	var avail := buf.size() - offset
	if avail < 2:
		return {"status": "need"}
	var b0 := buf[offset]
	var b1 := buf[offset + 1]
	var fin := (b0 & 0x80) != 0
	var rsv := b0 & 0x70
	var opcode := b0 & 0x0F
	var masked := (b1 & 0x80) != 0
	var len7 := b1 & 0x7F
	if rsv != 0:
		return {"status": "error", "code": CLOSE_PROTOCOL, "reason": "RSV-Bits gesetzt"}
	if not opcode in [OP_CONT, OP_TEXT, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG]:
		return {"status": "error", "code": CLOSE_PROTOCOL, "reason": "unbekannter Opcode %d" % opcode}
	if opcode >= 8 and (not fin or len7 > MAX_CONTROL):
		return {"status": "error", "code": CLOSE_PROTOCOL, "reason": "Steuerrahmen fragmentiert oder zu lang"}
	var pos := offset + 2
	var length := len7
	if len7 == 126:
		if avail < 4:
			return {"status": "need"}
		length = (buf[pos] << 8) | buf[pos + 1]
		pos += 2
	elif len7 == 127:
		if avail < 10:
			return {"status": "need"}
		if buf[pos] & 0x80:
			return {"status": "error", "code": CLOSE_PROTOCOL, "reason": "Länge ungültig"}
		length = 0
		for i in range(8):
			length = (length << 8) | buf[pos + i]
		pos += 8
	if length > max_payload:
		return {"status": "error", "code": CLOSE_TOO_BIG, "reason": "Rahmen zu groß (%d Byte)" % length}
	var key := PackedByteArray()
	if masked:
		if buf.size() < pos + 4:
			return {"status": "need"}
		key = buf.slice(pos, pos + 4)
		pos += 4
	if buf.size() < pos + length:
		return {"status": "need"}
	var payload := buf.slice(pos, pos + length)
	if masked:
		payload = apply_mask(payload, key)
	return {"status": "ok", "fin": fin, "opcode": opcode, "masked": masked, "payload": payload, "size": pos + length - offset}

static func valid_utf8(bytes: PackedByteArray) -> bool:
	# Strenge UTF-8-Prüfung (keine Überlängen, keine Surrogate, höchstens U+10FFFF) – Textrahmen müssen gültig sein (1007).
	var i := 0
	var n := bytes.size()
	while i < n:
		var c := bytes[i]
		if c < 0x80:
			i += 1
			continue
		var need := 0
		var minimum := 0
		var cp := 0
		if c >= 0xC2 and c <= 0xDF:
			need = 1
			minimum = 0x80
			cp = c & 0x1F
		elif c >= 0xE0 and c <= 0xEF:
			need = 2
			minimum = 0x800
			cp = c & 0x0F
		elif c >= 0xF0 and c <= 0xF4:
			need = 3
			minimum = 0x10000
			cp = c & 0x07
		else:
			return false
		if i + need >= n:
			return false
		for j in range(1, need + 1):
			var cc := bytes[i + j]
			if (cc & 0xC0) != 0x80:
				return false
			cp = (cp << 6) | (cc & 0x3F)
		if cp < minimum or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
			return false
		i += need + 1
	return true
