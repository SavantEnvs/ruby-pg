# PG::BinaryDecoder::CopyRow#decode: PGCOPY header, field count, field lengths (ext/pg_copy_coder.c),
# then each column through a binary decoder via a PG::TypeMapByColumn.
def fuzz_one(d)
  t { mk(BD::CopyRow).decode(d) }
  decs = binary_decoders
  tm = PG::TypeMapByColumn.new(Array.new(24) { |i| decs[i % decs.size] })
  t { mk(BD::CopyRow, type_map: tm).decode(d) }
end
