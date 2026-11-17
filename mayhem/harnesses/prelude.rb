# Shared helpers for the ruby-pg coder harnesses (prepended to every <target>.rb by build.sh).
# Each target defines fuzz_one(data), called once per input with a binary String.
TD = PG::TextDecoder
BD = PG::BinaryDecoder
TE = PG::TextEncoder
BE = PG::BinaryEncoder
# lib/pg.rb autoloads these coders, whose files call the extension's private init methods; the
# harness does not load lib/, so it calls them directly (they require 'date', 'ipaddr', 'bigdecimal').
# init_numeric calls back into this helper from lib/pg.rb.
def PG.require_bigdecimal_without_warning
  oldverb, $VERBOSE = $VERBOSE, nil
  require 'bigdecimal'
ensure
  $VERBOSE = oldverb
end
TD.send(:init_date)
TD.send(:init_inet)
TD.send(:init_numeric)
TE.send(:init_numeric)
BD.send(:init_date)
FUZZ_DEBUG = ENV.key?('FUZZ_CODER_DEBUG')

# Run one coder call; a Ruby exception (bad input rejected by the coder) is not a finding.
def t
  yield
rescue StandardError, LoadError => e
  warn "#{e.class}: #{e.message[0, 200]}" if FUZZ_DEBUG
  nil
end

# A fresh coder with its public setters applied. The gem's keyword initializer lives in lib/pg and
# also gives every PG::Binary* coder format 1 (binary); do the same here.
def mk(klass, **opts)
  c = klass.new
  c.format = 1 if klass.name.start_with?('PG::Binary')
  opts.each { |k, v| c.public_send("#{k}=", v) }
  c
end

def text_decoders
  [TD::String.new, TD::Integer.new, TD::Float.new, TD::Boolean.new, TD::Timestamp.new,
   TD::Date.new, TD::Bytea.new, TD::Inet.new, TD::Numeric.new, TD::Identifier.new,
   mk(TD::Array, elements_type: TD::Integer.new), TD::Record.new, TD::FromBase64.new,
   mk(TD::Timestamp, flags: PG::Coder::TIMESTAMP_DB_LOCAL | PG::Coder::TIMESTAMP_APP_LOCAL)]
end

def binary_decoders
  [mk(BD::String), mk(BD::Integer), mk(BD::Float), mk(BD::Boolean), mk(BD::Timestamp),
   mk(BD::Date), mk(BD::Bytea), mk(BD::Array, elements_type: mk(BD::Integer)),
   mk(BD::Array, elements_type: mk(BD::Timestamp)), mk(BD::ToBase64),
   mk(BD::ToBase64, elements_type: mk(BD::Integer)),
   mk(BD::Timestamp, flags: PG::Coder::TIMESTAMP_DB_LOCAL | PG::Coder::TIMESTAMP_APP_LOCAL)]
end

def utf8(s)
  s.dup.force_encoding(Encoding::UTF_8)
end
