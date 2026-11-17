# The encoders: PG::TextEncoder / PG::BinaryEncoder CopyRow, Array, Record, Identifier,
# QuotedLiteral, Bytea, ToBase64 / FromBase64 (ext/pg_text_encoder.c, ext/pg_binary_encoder.c,
# ext/pg_copy_coder.c, ext/pg_record_coder.c), quoting and buffer growth (pg_rb_str_ensure_capa).
# Input: fields separated by 0xFF. A field starting with 0xFE is nil; one starting with 0xFD is a
# nested array whose elements are separated by 0xFC. Byte 0 selects the string encoding (bit 0) and
# the array delimiter (bits 1-2).
def fuzz_one(d)
  return if d.empty?
  sel = d.getbyte(0)
  enc = sel & 1 == 0 ? Encoding::UTF_8 : Encoding::BINARY
  delim = [',', ';', '|', "\t"][(sel >> 1) & 3]
  str = ->(b) { b.dup.force_encoding(enc) }
  fields = d.byteslice(1..).b.split("\xFF".b, -1).map do |f|
    case f.getbyte(0)
    when 0xFE then nil
    when 0xFD then f.byteslice(1..).split("\xFC".b, -1).map { |e| e.getbyte(0) == 0xFE ? nil : str.(e) }
    else str.(f)
    end
  end
  flat = fields.map { |f| f.is_a?(Array) ? f.join : f }
  strs = flat.compact

  t { TE::CopyRow.new.encode(flat) }
  t { mk(TE::CopyRow, delimiter: delim, null_string: strs.first || '\\N').encode(flat) }
  t { mk(BE::CopyRow).encode(flat) }
  t { TE::Array.new.encode(fields) }
  t { mk(TE::Array, delimiter: delim, needs_quotation: sel & 8 == 0).encode(fields) }
  t { mk(TE::Array, elements_type: TE::Bytea.new).encode(fields) }
  t { mk(BE::Array, elements_type: mk(BE::String)).encode(fields) }
  t { mk(BE::Array, elements_type: mk(BE::Bytea)).encode(flat) }
  t { TE::Record.new.encode(fields) }
  t { TE::Identifier.new.encode(strs) }
  t { TE::QuotedLiteral.new.encode(flat.first) }
  t { mk(TE::QuotedLiteral, elements_type: TE::Array.new).encode(fields) }
  t { mk(TE::ToBase64, elements_type: TE::Array.new).encode(fields) }
  t { mk(BE::FromBase64, elements_type: mk(BE::String)).encode(strs.first) }
  strs.each do |s|
    t { TE::Identifier.new.encode(s) }
    t { TE::Bytea.new.encode(s) }
    t { TE::QuotedLiteral.new.encode(s) }
    t { TE::ToBase64.new.encode(s) }
  end
  # Round trip through the matching decoders, so encoded output is parsed again.
  t { TD::CopyRow.new.decode(TE::CopyRow.new.encode(flat)) }
  t { mk(BD::CopyRow).decode(mk(BE::CopyRow).encode(flat)) }
  t { TD::Array.new.decode(TE::Array.new.encode(fields)) }
  t { TD::Record.new.decode(TE::Record.new.encode(fields)) }
end
