# Loaded by mayhem/test.sh with `rspec --require`: the only upstream examples the oracle skips.
#
# spec/pg/connection_spec.rb's "via ... pg_service file and prefers ..." examples (8 with the sync_*
# repeat) assert `conninfo_hash[:service] == "mydb"` whenever PG.library_version >= 150000. libpq only
# reports the service name in PQconninfo() from PostgreSQL 18 on; Debian 13's libpq-dev is 17.x and
# returns nil there. Upstream CI runs these examples only against libpq 18 (source-gem.yml's PGVER
# matrix: 10/12/14 are below the guard), so they fail on any libpq 15-17 regardless of the extension.
RSpec.configure do |config|
  config.filter_run_excluding full_description: /\bpg_service file and prefers\b/
end
