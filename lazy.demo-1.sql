

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
      ( key->0 )::integer as n,
      ( key->1 )::integer as factor,
      ( LAZY.unwrap( value )  )::integer as product
    from LAZY.cache
    where bucket = 'MYSCHEMA.get_product' );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
create function MYSCHEMA.compute_product( ¶n integer, ¶factor integer )
  returns LAZY.jsonb_result immutable called on null input language plpgsql as $$ declare
  begin
    if ( ¶n is not distinct from null ) or ( ¶factor is not distinct from null ) then
      return LAZY.sad( 'will not produce result if any argument is null' ); end if;
    if ¶n != 13 then
      return LAZY.happy( ¶n * ¶factor ); end if;
    if ( ¶factor % 2 ) = 0 then
      return LAZY.sad( 'will not produce even multiples of 13' ); end if;
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
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => null                               -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  );

select
    r1.lnr - 1 as lnr,
    r1.line
  from regexp_split_to_table( LAZY._create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product',            -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA.compute_product',        -- optional, this x-or `perform_update` must be given
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => null                               -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  ), e'\n' ) with ordinality as r1 ( line, lnr );


select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.get_product( 4, 12 );
select * from MYSCHEMA.get_product( 5, 12 );
select * from MYSCHEMA.get_product( 6, 12 );
select * from MYSCHEMA.get_product( 60, 3 );
select * from MYSCHEMA.get_product( 13, 13 );
select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.products;

do $$ begin
  perform MYSCHEMA.get_product( 13, 12 );
  exception when others then
    if sqlstate !~ '^LZ' then raise; end if;
    raise notice '(sqlstate) sqlerrm: (%) %', sqlstate, sqlerrm;
  end; $$;

select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.products;

/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit


select * from CATALOG.catalog where schema = 'myschema';

