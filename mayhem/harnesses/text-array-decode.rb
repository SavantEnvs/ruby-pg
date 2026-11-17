# PG::TextDecoder::Array#decode: dimension prefix, nesting, quoting and escapes
# (ext/pg_text_decoder.c), with each kind of element decoder.
# Input: byte 0 = bits 0-1 delimiter, bit 7 binary encoding; then the array literal.
def fuzz_one(d)
  return if d.empty?
  sel = d.getbyte(0)
  s = d.byteslice(1..)
  s = utf8(s) if sel & 0x80 == 0
  delim = [',', ';', '|', "\t"][sel & 3]
  t { mk(TD::Array, delimiter: delim).decode(s) }
  inner = mk(TD::Array, delimiter: delim, elements_type: TD::Integer.new)
  (text_decoders + [inner]).each do |el|
    t { mk(TD::Array, delimiter: delim, elements_type: el).decode(s) }
  end
end
