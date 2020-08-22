

-- \set ECHO queries

/* ###################################################################################################### */
\ir './_trm.sql'
-- \ir './set-signal-color.sql'
-- \ir './test-begin.sql'
-- \pset pager on
\timing off
-- ---------------------------------------------------------------------------------------------------------
begin transaction;

\ir './050-lazy.sql'
\set filename intershop-lazy/lazy.demo-1.sql
\set signal :red

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
drop schema if exists MYSCHEMA cascade; create schema MYSCHEMA;

-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create view MYSCHEMA.products as ( select
      ( LAZY.nullify( key->0 ) )::integer as n,
      ( LAZY.nullify( key->1 ) )::integer as factor,
      ( LAZY.nullify( value  ) )::integer as product
    from LAZY.cache
    where bucket = 'MYSCHEMA.get_product' );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
create function MYSCHEMA.compute_product( ¶n integer, ¶factor integer )
  returns integer immutable called on null input language plpgsql as $$ declare
  begin
    if ¶n != 13 then return ¶n * ¶factor; end if;
    return null; end; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product',            -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA.compute_product',        -- optional, this x-or `perform_update` must be given
  perform_update  => null                               -- optional, this x-or `get_update` must be given
  );

select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.get_product( 4, 12 );
select * from MYSCHEMA.get_product( 5, 12 );
select * from MYSCHEMA.get_product( 6, 12 );
select * from MYSCHEMA.get_product( 60, 3 );
select * from MYSCHEMA.get_product( 13, 13 );
select * from MYSCHEMA.get_product( 1, null );
select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.products;


/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit


select * from CATALOG.catalog where schema = 'myschema';

