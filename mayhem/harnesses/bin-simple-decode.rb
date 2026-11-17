# The fixed-width binary decoders and their length checks (ext/pg_binary_decoder.c), and
# ToBase64 (base64_encode in ext/pg_util.c).
# Input: byte 0 = coder flags (low 4 bits) for Timestamp/Date; then the value bytes.
def fuzz_one(d)
  return if d.empty?
  flags = d.getbyte(0) & 0x0f
  v = d.byteslice(1..)
  binary_decoders.each do |dec|
    t { dec.decode(v) }
  end
  t { mk(BD::Timestamp, flags: flags).decode(v) }
  t { mk(BD::Date, flags: flags).decode(v) }
end
