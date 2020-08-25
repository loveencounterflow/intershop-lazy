

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
\set filename intershop-lazy/lazy.demo-2.sql
\set signal :red

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
drop schema if exists MYSCHEMA cascade; create schema MYSCHEMA;

-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create view MYSCHEMA.sums as ( select
      ( LAZY.nullify( key->0 ) )::integer as a,
      ( LAZY.nullify( key->1 ) )::integer as b,
      ( LAZY.nullify( value  ) )::integer as sum
    from LAZY.cache
    where bucket = 'yeah! sums!'
    order by a desc, b desc );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
create function MYSCHEMA.insert_sums_single_row( ¶a integer, ¶b integer )
  returns void volatile called on null input language plpgsql as $$ begin
    raise notice 'MYSCHEMA.insert_sums( %, % )', ¶a, ¶b;
    insert into LAZY.cache ( bucket, key, value ) values
      ( 'yeah! sums!', to_jsonb( array[ ¶a, ¶b ] ), to_jsonb( ¶a + ¶b ) );
    end; $$;

create function MYSCHEMA.insert_sums( ¶a integer, ¶b integer )
  returns void volatile called on null input language plpgsql as $$ begin
    raise notice 'MYSCHEMA.insert_sums( %, % )', ¶a, ¶b;
    insert into LAZY.cache ( bucket, key, value ) select
        'yeah! sums!'                                 as bucket,
        r2.key                                        as key,
        r3.value                                      as value
      from generate_series( ¶b - 1, ¶b + 1 )        as r1 ( bb    ),
      lateral to_jsonb( array[ ¶a, r1.bb ] )        as r2 ( key   ),
      lateral to_jsonb( ¶a + r1.bb )                as r3 ( value )
      where not exists ( select 1 from LAZY.cache as r4 where ( r4.key = r2.key ) );
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_sum',
  parameter_names => '{¶a,¶b}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',
  bucket          => 'yeah! sums!',
  perform_update  => 'MYSCHEMA.insert_sums' );

create table MYSCHEMA.fancy_sums (
  a         integer,
  b         integer,
  result    integer );

insert into MYSCHEMA.fancy_sums ( a, b ) select 7, b from generate_series( 1, 10 ) as x ( b );
update MYSCHEMA.fancy_sums set result = MYSCHEMA.get_sum( a, b );
select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.sums;

/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit


select * from CATALOG.catalog where schema = 'myschema';

