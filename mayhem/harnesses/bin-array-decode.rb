# PG::BinaryDecoder::Array#decode: ndim, flags, element OID, dimension sizes and lower bounds,
# element lengths (ext/pg_binary_decoder.c), with each kind of element decoder.
def fuzz_one(d)
  t { mk(BD::Array).decode(d) }
  nested = mk(BD::Array, elements_type: mk(BD::Integer))
  (binary_decoders + [nested]).each do |el|
    t { mk(BD::Array, elements_type: el).decode(d) }
  end
end
