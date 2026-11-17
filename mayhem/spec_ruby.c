/*
 * mayhem/spec_ruby.c: a ruby interpreter with ruby-pg's extension (the ext/ sources, built with the project's
 * normal flags) linked in statically and registered as the feature `pg_ext`, so `require 'pg'` from
 * lib/ uses this build. mayhem/test.sh runs upstream's rspec suite with it.
 */
#include <ruby.h>

void Init_pg_ext(void);

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  {
    RUBY_INIT_STACK;
    ruby_init();
    void *node = ruby_options(argc, argv); /* load path, encodings, rubygems; compiles the program */
    Init_pg_ext();
    rb_provide("pg_ext.so");               /* `require 'pg_ext'` (lib/pg.rb) is now satisfied */
    return ruby_run_node(node);
  }
}
