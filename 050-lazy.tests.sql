

-- \set ECHO queries

/* ###################################################################################################### */
\ir './_trm.sql'
-- \ir './set-signal-color.sql'
-- \ir './test-begin.sql'
\pset pager off
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
select * from LAZY.nullify( ( 'null'::jsonb, null )::LAZY.jsonb_result );
select * from LAZY.nullify( (   null::jsonb, null )::LAZY.jsonb_result );
select * from LAZY.nullify( null::LAZY.jsonb_result );

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
      ( value                                             )::integer as product
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
create function MYSCHEMA._update_products_cache( ¶n integer, ¶factor integer, ¶bucket text default 'MYSCHEMA.products_1' )
  returns void volatile called on null input language plpgsql as $$ declare
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
create function MYSCHEMA._perform_costly_computation( ¶n integer, ¶factor integer )
  returns jsonb immutable called on null input language plpgsql as $$ declare
  begin
    if ¶n != 13 then  return ¶n * ¶factor;
    else              return null; end if;
    end; $$;


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 6 }———:reset

 create function MYSCHEMA.get_product_m1( ¶n integer, ¶factor integer )            /*^1^*/
   returns integer                                                                /*^2^*/
   called on null input volatile language plpgsql as $f$                          /*^3^*/
   declare                                                                        /*^4^*/
     ¶key    jsonb := MYSCHEMA._get_product_key( ¶n, ¶factor );                   /*^5^*/
     ¶rows   jsonb[];                                                             /*^6^*/
     ¶value  jsonb;                                                               /*^7^*/
   begin                                                                          /*^8^*/
   -- ---------------------------------------------------                         /*^9^*/
   -- Try to retrieve and return value from cache:                                /*^9^*/
   ¶rows := ( select array_agg( value ) from LAZY.cache                           /*^10^*/
    where bucket = 'MYSCHEMA.get_product_m1' and key = ¶key );                          /*^11^*/
  if array_length( ¶rows, 1 ) = 1 then                                            /*^12^*/
    ¶value := ¶rows[ 1 ];                                                         /*^13^*/
  else                                                                            /*^13^*/
    ¶value := null::jsonb;                                            /*^13^*/
    end if;                                                                       /*^13^*/
  -- -----------------------------------------------------                        /*^14^*/
  perform MYSCHEMA._update_products_cache( ¶n, ¶factor, 'MYSCHEMA.get_product_m1' );                         /*^19^*/
   -- ---------------------------------------------------                         /*^9^*/
   -- Try to retrieve and return value from cache:                                /*^9^*/
  ¶rows := ( select array_agg( value ) from LAZY.cache                           /*^10^*/
    where bucket = 'MYSCHEMA.get_product_m1' and key = ¶key );                          /*^11^*/
  if array_length( ¶rows, 1 ) = 1 then                                            /*^12^*/
    return ( ¶rows[ 1 ] )::integer; end if;                                                         /*^13^*/
  ¶value := null::jsonb;                                            /*^13^*/
  insert into LAZY.cache ( bucket, key, value ) values                            /*^21^*/
    ( 'MYSCHEMA.get_product_m1', ¶key, ¶value );                                        /*^22^*/
    return ( ¶value )::integer;                                /*^23^*/
  end; $f$;                                                                       /*^24^*/

-- ---------------------------------------------------------------------------------------------------------
 create function MYSCHEMA.get_product_m2( ¶n integer, ¶factor integer )            /*^1^*/
   returns integer                                                                /*^2^*/
   called on null input volatile language plpgsql as $f$                          /*^3^*/
   declare                                                                        /*^4^*/
     ¶key    jsonb := jsonb_build_array( ¶n, ¶factor );                           /*^5^*/
     ¶rows   jsonb[];                                                             /*^6^*/
     ¶value  jsonb;                                                               /*^7^*/
   begin                                                                          /*^8^*/
   -- ---------------------------------------------------                         /*^9^*/
   -- Try to retrieve and return value from cache:                                /*^9^*/
   ¶rows := ( select array_agg( value ) from LAZY.cache                           /*^10^*/
    where bucket = 'MYSCHEMA.get_product_m2' and key = ¶key );                     /*^11^*/
  if array_length( ¶rows, 1 ) = 1 then                                            /*^12^*/
    ¶value := ¶rows[ 1 ];                                                         /*^13^*/
  else                                                                            /*^13^*/
    ¶value := null::jsonb;                                                        /*^13^*/
    end if;                                                                       /*^13^*/
  -- -----------------------------------------------------                        /*^14^*/
  -- Compute value and put it into cache:                                         /*^16^*/
  ¶value := MYSCHEMA._perform_costly_computation( ¶n, ¶factor );                  /*^15^*/
  insert into LAZY.cache ( bucket, key, value ) values                            /*^16^*/
    ( 'MYSCHEMA.get_product_m2', ¶key, ¶value );                                   /*^17^*/
    return ¶value::integer;                              /*^18^*/
  end; $f$;                                                                       /*^24^*/


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
select
    r1.lnr - 1 as lnr,
    r1.line
  from regexp_split_to_table( LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_1',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to JSONB value
  bucket          => 'MYSCHEMA.products_1',             -- optional, defaults to `function_name`
  get_key         => 'MYSCHEMA._get_product_key',       -- optional, default is JSON list / object of values
  get_update      => null,                              -- optional, this x-or `perform_update` must be given
  perform_update  => 'MYSCHEMA._update_products_cache'  -- optional, this x-or `get_update` must be given
  ), e'\n' ) with ordinality as r1 ( line, lnr );

select
    r1.lnr - 1 as lnr,
    r1.line
  from regexp_split_to_table( LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product_2',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to JSONB value
  bucket          => null,                              -- optional, defaults to `function_name`
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA._perform_costly_computation',      -- optional, this x-or `perform_update` must be given
  perform_update  => null                               -- optional, this x-or `get_update` must be given
  ), e'\n' ) with ordinality as r1 ( line, lnr );

-- select * from LAZY.cache order by bucket, key;
-- select * from MYSCHEMA.get_product_1( 4, 12 );
-- select * from MYSCHEMA.get_product_1( 4, 12 );
-- select * from MYSCHEMA.get_product_1( 5, 12 );
-- select * from MYSCHEMA.get_product_1( 6, 12 );
-- select * from MYSCHEMA.get_product_1( 60, 3 );
-- select * from MYSCHEMA.get_product_2( 4, 12 );
-- select * from MYSCHEMA.get_product_2( 4, 12 );
-- select * from MYSCHEMA.get_product_2( 5, 12 );
-- select * from MYSCHEMA.get_product_2( 6, 12 );
-- select * from MYSCHEMA.get_product_2( 60, 3 );
-- select * from LAZY.cache order by bucket, key;
-- \quit
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
  matcher       text,
  result        text );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
-- insert into LAZY_X.probes_and_matchers_1 ( title, probe, matcher ) values
--   ( 'get_product_1',             '{12,12}',         'helo'                      );
-- update LAZY_X.probes_and_matchers_1 set result = LAZY.escape_text( probe ) where title = 'escape_text';

insert into LAZY_X.probes_and_matchers_2 ( title, probe_1, probe_2, matcher ) values
  ( 'get_product_m1', '0',   '1',      '0'   ),
  ( 'get_product_m1', '1',   '1',      '1'   ),
  ( 'get_product_m1', '13',  '12',     null  ),
  ( 'get_product_m1', '12',  '12',     '144' ),
  ( 'get_product_m1', '3',   '9',      '27'  ),
  ( 'get_product_m2', '0',   '1',      '0'   ),
  ( 'get_product_m2', '1',   '1',      '1'   ),
  ( 'get_product_m2', '13',  '12',     null  ),
  ( 'get_product_m2', '3',   '9',      '27'  ),
  ( 'get_product_m2', '12',  '12',     '144' ),
  ( 'get_product_1', '0',   '1',      '0'   ),
  ( 'get_product_1', '1',   '1',      '1'   ),
  ( 'get_product_1', '13',  '12',     null  ),
  ( 'get_product_1', '12',  '12',     '144' ),
  ( 'get_product_1', '3',   '9',      '27'  );
  -- ( 'get_product_2', '0',   '1',      '0'   ),
  -- ( 'get_product_2', '1',   '1',      '1'   ),
  -- ( 'get_product_2', '13',  '12',     null  ),
  -- ( 'get_product_2', '3',   '9',      '27'  ),
  -- ( 'get_product_2', '12',  '12',     '144' );



-- ---------------------------------------------------------------------------------------------------------
do $outer$
  declare
    ¶fname  text;
    ¶sql    text := $xxx$ do $$ declare
      ¶row    record;
      ¶result text;
    begin
      for ¶row in ( select * from LAZY_X.probes_and_matchers_2 where title = %L ) loop
        ¶result = MYSCHEMA.%s( ¶row.probe_1::integer, ¶row.probe_2::integer )::text;
        update LAZY_X.probes_and_matchers_2 set result = ¶result where id = ¶row.id;
        end loop;
      end; $$; $xxx$;
  begin
    for ¶fname in ( select distinct title from LAZY_X.probes_and_matchers_2 order by title ) loop
      execute format( ¶sql, ¶fname, ¶fname );
      end loop;
    end;
$outer$;

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
    lateral ( select matcher::jsonb                          )  as r3 ( result ),
    lateral ( select coalesce( r3.result = r2.value, false ) )  as r4 ( is_ok )
    where v1.title = 'get_product_2'
    order by r2.key );

select * from LAZY_X.result_comparison;

-- ---------------------------------------------------------------------------------------------------------
insert into INVARIANTS.tests select
    'LAZY'                                                              as module,
    title                                                               as title,
    row( result, matcher )::text                                        as values,
    ( result is null and matcher is null ) or ( result = matcher )      as is_ok
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
select * from LAZY.cache order by bucket, key;


-- select * from INVARIANTS.tests;
select * from INVARIANTS.violations;
-- select count(*) from ( select * from INVARIANTS.violations limit 1 ) as x;
-- select count(*) from INVARIANTS.violations;
do $$ begin perform INVARIANTS.validate(); end; $$;


/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit




