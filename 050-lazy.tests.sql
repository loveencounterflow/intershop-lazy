

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
\set filename intershop-lazy/050-lazy.tests.sql
\set signal :red
do $$ begin perform log( 'LAZY tests' ); end; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
drop schema if exists LAZY_X cascade; create schema LAZY_X;



-- do $$
--   declare
--     ¶value  LAZY.jsonb_result;
--     ¶n      integer := 3;
--     ¶factor integer := 3;
--   begin
--    raise notice 'x1';
--    ¶value := ( '42'::jsonb, null )::LAZY.jsonb_result;
--    ¶value := LAZY.happy( 44 );
--    ¶value := LAZY.sad( 'error' );
--    /*-14-  ¶value := /*-(gu-*/ case ¶n when 13 then LAZY.happy( null::jsonb ) else LAZY.happy( ¶n * ¶factor ) end; /*-gu)*/
--    raise notice 'x2 %', ¶value;
--   end; $$;
-- \quit
-- */

/*
create table LAZY_X.the_truth_about_null (
  probe LAZY.jsonb_result,
  is_null     text              ,
  is_not_null text              ,
  is_distinct_from_null text    ,
  is_not_distinct_from_null text
  );

create function LAZY_X.truth( boolean ) returns text called on null input language sql as
  $$ select case when $1 is null then 'NULL' else case when $1 then 'true' else '-' end end; $$;

insert into LAZY_X.the_truth_about_null ( probe ) values
  ( null::LAZY.jsonb_result                                   ),
  ( ( to_jsonb( 42 ),   null            )::LAZY.jsonb_result  ),
  ( ( null,             'error message' )::LAZY.jsonb_result  ),
  ( ( null,             null            )::LAZY.jsonb_result  );

update LAZY_X.the_truth_about_null as r1 set
    is_null                   = LAZY_X.truth( r1.probe is null                  ),
    is_not_null               = LAZY_X.truth( r1.probe is not null              ),
    is_distinct_from_null     = LAZY_X.truth( r1.probe is distinct from null    ),
    is_not_distinct_from_null = LAZY_X.truth( r1.probe is not distinct from null )
  from LAZY_X.the_truth_about_null as r2
  where r1.probe = r2.probe;

update LAZY_X.the_truth_about_null as r1 set
    is_null                   = LAZY_X.truth( r1.probe is null                  ),
    is_not_null               = LAZY_X.truth( r1.probe is not null              ),
    is_distinct_from_null     = LAZY_X.truth( r1.probe is distinct from null    ),
    is_not_distinct_from_null = LAZY_X.truth( r1.probe is not distinct from null )
  from LAZY_X.the_truth_about_null as r2
  where r1.probe is null and r2.probe is null;


select * from LAZY_X.the_truth_about_null order by probe;
select * from LAZY._normalize( ( 'null'::jsonb, null )::LAZY.jsonb_result );
select * from LAZY._normalize( (   null::jsonb, null )::LAZY.jsonb_result );
select * from LAZY._normalize( null::LAZY.jsonb_result );

\quit
*/


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
drop schema if exists MYSCHEMA cascade; create schema MYSCHEMA;

\echo :signal ———{ :filename 3 }———:reset
create view MYSCHEMA.products as ( select
      ( regexp_replace( key#>>'{}',    ' times .*$', '' ) )::integer as n,
      ( regexp_replace( key#>>'{}', '^.* times ',    '' ) )::integer as factor,
      ( LAZY.unwrap( value )  )::integer as product
    from LAZY.cache
    where bucket = 'MYSCHEMA.products' );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 4 }———:reset
create function MYSCHEMA._get_product_key( ¶n integer, ¶factor integer )
  returns jsonb immutable strict language sql as $$ select
    ( format( '"%s times %s"', ¶n, ¶factor ) )::jsonb; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
-- ### NOTE consider to allow variant where update method returns key, value instead of inserting itself;
-- the latter is more general as it may insert an arbitrary number of adjacent / related / whatever items
create function MYSCHEMA._update_products_cache( ¶n integer, ¶factor integer )
  returns void volatile called on null input language plpgsql as $$ declare
    ¶bucket text  :=  'MYSCHEMA.products';
    ¶key    jsonb :=  MYSCHEMA._get_product_key( ¶n, ¶factor );
  begin
    insert into LAZY.cache ( bucket, key, value ) values
      ( ¶bucket, ¶key, MYSCHEMA._perform_costly_computation( ¶n, ¶factor ) );
    -- insert into LAZY.cache ( bucket, key, value ) select
    --     ¶bucket,
    --     ¶key,
    --     MYSCHEMA._perform_costly_computation( ¶n, r1.factor )
    --   from generate_series( ¶factor - 1, ¶factor + 1 ) as r1 ( factor )
    --   on conflict ( bucket, key ) do nothing;
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
-- ### NOTE consider to allow variant where update method returns key, value instead of inserting itself;
-- the latter is more general as it may insert an arbitrary number of adjacent / related / whatever items
create function MYSCHEMA._perform_costly_computation( ¶n integer, ¶factor integer )
  returns LAZY.jsonb_result immutable called on null input language plpgsql as $$ declare
  begin
    if ( ¶n is not distinct from null ) or ( ¶factor is not distinct from null ) then
      return LAZY.sad( 'will not produce result if any argument is null' );
      end if;
    if ¶n != 13 then
      return LAZY.happy( ¶n * ¶factor );
    else
      if ( ¶factor % 2 ) = 0 then
        return LAZY.sad( 'will not produce even multiples of 13' );
      else
        return null;
        end if;
      end if;
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 6 }———:reset
-- ### NOTE consider to allow variant where update method returns key, value instead of inserting itself;
-- the latter is more general as it may insert an arbitrary number of adjacent / related / whatever items
create function MYSCHEMA.get_product_0( ¶n integer, ¶factor integer )
  returns integer volatile strict language plpgsql as $$ declare
    ¶bucket text  :=  'MYSCHEMA.products';
    ¶key    jsonb :=  MYSCHEMA._get_product_key( ¶n, ¶factor );
    ¶value  jsonb;
  begin
    ¶value := ( select value from LAZY.cache where bucket = ¶bucket and ¶key = key );
    if ¶value is not null then return ¶value::integer; end if;
    perform MYSCHEMA._update_products_cache( ¶n, ¶factor );
    ¶value := ( select value from LAZY.cache where bucket = ¶bucket and ¶key = key );
    if ¶value is not null then return ¶value::integer; end if;
    raise sqlstate 'XXX02' using message = format( '#XXX02-1 Key Error: unable to retrieve result for ¶n: %s, ¶factor: %s', ¶n, ¶factor );
    end; $$;

create function MYSCHEMA.cast_product( ¶value jsonb )
  returns integer immutable called on null input language sql as
  $$ select ¶value::integer; $$;

select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_1',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  bucket          => 'MYSCHEMA.products',               -- optional, defaults to `function_name`
  get_key         => 'MYSCHEMA._get_product_key',       -- optional, default is JSON list / object of values
  get_update      => null,                              -- optional, this x-or `perform_update` must be given
  perform_update  => 'MYSCHEMA._update_products_cache', -- optional, this x-or `get_update` must be given
  caster          => null                               -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  );

select
    r1.lnr - 1 as lnr,
    r1.line
  from regexp_split_to_table( LAZY._create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_1',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  bucket          => 'MYSCHEMA.products',               -- optional, defaults to `function_name`
  get_key         => 'MYSCHEMA._get_product_key',       -- optional, default is JSON list / object of values
  get_update      => null,                              -- optional, this x-or `perform_update` must be given
  perform_update  => 'MYSCHEMA._update_products_cache', -- optional, this x-or `get_update` must be given
  caster          => null                               -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  ), e'\n' ) with ordinality as r1 ( line, lnr );

select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_2',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  bucket          => null,                              -- optional, defaults to `function_name`
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA._perform_costly_computation',      -- optional, this x-or `perform_update` must be given
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => 'MYSCHEMA.cast_product'            -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  );

select
    r1.lnr - 1 as lnr,
    r1.line
  from regexp_split_to_table( LAZY._create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_2',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  bucket          => null,                              -- optional, defaults to `function_name`
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA._perform_costly_computation( ¶n, ¶factor )',      -- optional, this x-or `perform_update` must be given
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => 'MYSCHEMA.cast_product'            -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  ), e'\n' ) with ordinality as r1 ( line, lnr );

-- select * from LAZY.cache order by bucket, key;
-- select * from MYSCHEMA.get_product_1( 4, 12 );
-- select * from MYSCHEMA.get_product_1( 5, 12 );
-- select * from MYSCHEMA.get_product_1( 6, 12 );
-- select * from MYSCHEMA.get_product_2( 60, 3 );
-- select * from LAZY.cache order by bucket, key;
-- select * from MYSCHEMA.products;
-- select * from CATALOG.catalog where schema = 'myschema';

-- select * from MYSCHEMA.get_product_1( 13, 12 );


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
create table LAZY_X.probes_and_matchers_2 (
  id            bigint generated always as identity primary key,
  title         text,
  probe_1       text,
  probe_2       text,
  matcher_ok    text,
  matcher_error text,
  result_ok     text,
  result_error  text );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
-- insert into LAZY_X.probes_and_matchers_1 ( title, probe, matcher_ok ) values
--   ( 'get_product_1',             '{12,12}',         'helo'                      );
-- update LAZY_X.probes_and_matchers_1 set result = LAZY.escape_text( probe ) where title = 'escape_text';

insert into LAZY_X.probes_and_matchers_2 ( title, probe_1, probe_2, matcher_ok, matcher_error ) values
  ( 'get_product_1', '0',   '1',      '0',   null           ),
  ( 'get_product_1', '1',   '1',      '1',   null           ),
  ( 'get_product_1', '13',  '12',     null,  'LZE00 will not produce even multiples of 13'        ),
  ( 'get_product_1', '12',  '12',     '144', null           ),
  ( 'get_product_1', '3',   '9',      '27',  null           ),
  ( 'get_product_2', '0',   '1',      '0',   null           ),
  ( 'get_product_2', '1',   '1',      '1',   null           ),
  ( 'get_product_2', '13',  '12',     null,  'LZE00 will not produce even multiples of 13'        ),
  ( 'get_product_2', '3',   '9',      '27',  null           ),
  ( 'get_product_2', '12',  '12',     '144', null           );

-- ---------------------------------------------------------------------------------------------------------
do $$
declare
    ¶row    record;
    ¶result text;
  begin
    for ¶row in ( select * from LAZY_X.probes_and_matchers_2 where title = 'get_product_1' ) loop begin
      ¶result = MYSCHEMA.get_product_1( ¶row.probe_1::integer, ¶row.probe_2::integer )::text;
      update LAZY_X.probes_and_matchers_2 set result_ok = ¶result where id = ¶row.id;
      -- ...................................................................................................
      -- exception when sqlstate 'LZ120' then
      exception when others then
        if sqlstate !~ '^LZ' then raise; end if;
        raise notice '(sqlstate) sqlerrm: (%) %', sqlstate, sqlerrm;
        -- raise notice 'error:  %', row( sqlstate, sqlerrm )::LAZY.error;
        -- raise notice 'result: %', row( null, sqlstate, sqlerrm )::LAZY.jsonb_result;
        update LAZY_X.probes_and_matchers_2 set result_error = sqlerrm where id = ¶row.id;
      end; end loop;
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
do $$
declare
    ¶row    record;
    ¶result text;
  begin
    for ¶row in ( select * from LAZY_X.probes_and_matchers_2 where title = 'get_product_2' ) loop begin
      ¶result = MYSCHEMA.get_product_2( ¶row.probe_1::integer, ¶row.probe_2::integer )::text;
      update LAZY_X.probes_and_matchers_2 set result_ok = ¶result where id = ¶row.id;
      -- ...................................................................................................
      -- exception when sqlstate 'LZ120' then
      exception when others then
        if sqlstate !~ '^LZ' then raise; end if;
        raise notice '(sqlstate) sqlerrm: (%) %', sqlstate, sqlerrm;
        update LAZY_X.probes_and_matchers_2 set result_error = sqlerrm where id = ¶row.id;
      end; end loop;
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
create view LAZY_X.result_comparison as (
  with v1 as ( select
      *,
      to_jsonb( array[ probe_1::integer, probe_2::integer ] ) as key
    from LAZY_X.probes_and_matchers_2 )
  select
      v1.id,
      v1.probe_1,
      v1.probe_2,
      r3.result,
      r2.key,
      r2.value,
      r4.is_ok
    from v1
    left join LAZY.cache as r2 on r2.key = v1.key,
    lateral ( select ( matcher_ok::jsonb, matcher_error )::LAZY.jsonb_result ) as r3 ( result ),
    lateral ( select coalesce( r3.result = r2.value, false ) ) as r4 ( is_ok )
    where v1.title = 'get_product_2'
    order by r2.key );

select * from LAZY_X.result_comparison;

-- ---------------------------------------------------------------------------------------------------------
insert into INVARIANTS.tests select
    'LAZY'                                                              as module,
    title                                                               as title,
    row( result_ok, result_error, matcher_ok, matcher_error )::text     as values,
    case when ( result_error is null )
      then ( result_ok::integer = matcher_ok::integer )
      else ( result_error       = matcher_error       ) end             as is_ok
  from LAZY_X.probes_and_matchers_2 as r1;

-- ---------------------------------------------------------------------------------------------------------
/* making sure that all tests get an entry in LAZY.cache: */
insert into INVARIANTS.tests select
    'LAZY'                                                              as module,
    'cache for ' || probe_1 || ', ' || probe_2                          as title,
    row( result )::text                                                 as values,
    is_ok                                                               as is_ok
  from LAZY_X.result_comparison as r1;


-- ---------------------------------------------------------------------------------------------------------
select * from LAZY_X.probes_and_matchers_2 order by id;
-- update LAZY.cache set value = LAZY.happy( 99 ) where bucket = 'MYSCHEMA.products' and key = '"3 times 9"'::jsonb;
-- insert into LAZY.cache ( bucket, key, value ) values ( 'xxx', '"foo1"', null::LAZY.jsonb_result );
-- insert into LAZY.cache ( bucket, key, value ) values ( 'xxx', '"foo2"', ( 'null'::jsonb, null )::LAZY.jsonb_result );
select * from LAZY.cache order by key;


-- select * from INVARIANTS.tests;
select * from INVARIANTS.violations;
-- select count(*) from ( select * from INVARIANTS.violations limit 1 ) as x;
-- select count(*) from INVARIANTS.violations;
do $$ begin perform INVARIANTS.validate(); end; $$;


/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit




