# PG::TextDecoder::Record#decode: the composite-type parser (ext/pg_record_coder.c), plain and with
# a type map of text decoders including nested records and arrays.
def fuzz_one(d)
  s = utf8(d)
  t { TD::Record.new.decode(s) }
  t { TD::Record.new.decode(d) }
  decs = text_decoders + [mk(TD::Record, type_map: PG::TypeMapByColumn.new([TD::Integer.new, nil, TD::Float.new]))]
  tm = PG::TypeMapByColumn.new(Array.new(32) { |i| decs[i % decs.size] })
  t { mk(TD::Record, type_map: tm).decode(s) }
end
