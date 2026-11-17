# The scalar text decoders: Inet (IPv4/IPv6/CIDR), Bytea (hex and escape forms), Identifier,
# FromBase64 (base64_decode in ext/pg_util.c), Numeric, Integer, Float, Boolean, String.
def fuzz_one(d)
  s = utf8(d)
  text_decoders.each do |dec|
    t { dec.decode(s) }
  end
  t { TD::Bytea.new.decode(d) }
  t { TD::FromBase64.new.decode(d) }
  t { mk(TD::FromBase64, elements_type: TD::Integer.new).decode(s) }
end
