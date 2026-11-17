# PG::TextDecoder::CopyRow#decode: COPY text row parser with backslash escapes, delimiter and
# null_string (ext/pg_copy_coder.c), then each column through a text decoder via a type map.
# Input: byte 0 = delimiter, byte 1 = bits 0-2 null_string length, bit 3 encoding; then null_string;
# then the row.
def fuzz_one(d)
  return if d.bytesize < 2
  sel = d.getbyte(1)
  nlen = sel & 7
  null_string = d.byteslice(2, nlen) || ''
  row = d.byteslice((2 + nlen)..) || ''
  row = utf8(row) if sel & 8 == 0
  t { mk(TD::CopyRow, delimiter: d.byteslice(0, 1), null_string: null_string).decode(row) }
  t { TD::CopyRow.new.decode(row) }
  decs = text_decoders
  tm = PG::TypeMapByColumn.new(Array.new(32) { |i| decs[i % decs.size] })
  t { mk(TD::CopyRow, delimiter: d.byteslice(0, 1), null_string: null_string, type_map: tm).decode(row) }
end
