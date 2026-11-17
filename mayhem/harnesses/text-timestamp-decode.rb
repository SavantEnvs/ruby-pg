# PG::TextDecoder::Timestamp / Date #decode: the hand-written timestamp and date parser
# (ext/pg_text_decoder.c) under every combination of the TIMESTAMP_* and FORMAT_ERROR_* flags.
# Input: byte 0 = coder flags (low 4 bits); then the timestamp text.
def fuzz_one(d)
  return if d.empty?
  flags = d.getbyte(0) & 0x0f
  s = utf8(d.byteslice(1..))
  t { mk(TD::Timestamp, flags: flags).decode(s) }
  t { mk(TD::Date, flags: flags).decode(s) }
  t { mk(TD::Array, elements_type: mk(TD::Timestamp, flags: flags)).decode(s) }
end
