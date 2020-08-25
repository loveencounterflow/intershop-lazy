

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
drop schema if exists NLEX cascade; create schema NLEX;

-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
-- ---------------------------------------------------------------------------------------------------------
create type NLEX.german_word as (
  singular    text,
  gender      text,
  plural      text );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create type NLEX.english_and_german as (
  english     text,
  german      NLEX.german_word );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create view NLEX.lexicon as ( select
      key->>0               as english,
      (r2.value).singular   as singular,
      (r2.value).gender     as gender,
      (r2.value).plural     as plural
    from LAZY.cache                                 as r1,
    lateral ( select r1.value::NLEX.german_word )   as r2
    where bucket = 'lexicon/en/de'
    order by english );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
create function NLEX.insert_german_word( ¶english text )
  returns void volatile called on null input language plpgsql as $$
  declare
    ¶value NLEX.german_word;
  begin
    case ¶english
      when 'peacock'  then  ¶value := ( 'Pfau', 'm', 'Pfauen' )::NLEX.german_word;
      when 'mouse'    then  ¶value := ( 'Maus', 'f', 'Mäuse'  )::NLEX.german_word;
      when 'house'    then  ¶value := ( 'Haus', 'n', 'Häuser' )::NLEX.german_word;
      else                  ¶value := null::NLEX.german_word;
      end case;
    raise notice using message = format( '^3334^ %L <- insert_german_word( %L )',
      ¶value, ¶english );
    insert into LAZY.cache ( bucket, key, value ) values
      ( 'lexicon/en/de', jsonb_build_array( ¶english ), ¶value );
    end; $$;


-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
select LAZY.create_lazy_producer(
  function_name   => 'NLEX.translate_to_german',
  parameter_names => '{¶english}',
  parameter_types => '{text}',
  return_type     => 'NLEX.german_word',
  bucket          => 'lexicon/en/de',
  perform_update  => 'NLEX.insert_german_word' );

create view NLEX.inputs as
  ( select null::text as english where false ) union all
values
  ( 'peacock' ),
  ( 'mouse'   ),
  ( 'house'   );

select * from NLEX.inputs;

select
    *
  from NLEX.inputs                                as r1 ( english ),
  lateral NLEX.translate_to_german( r1.english )  as r2;
\echo :reverse:steel' LAZY.cache '
select * from LAZY.cache;
\echo :reverse:steel' NLEX.lexicon '
select * from NLEX.lexicon;


/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit


select * from CATALOG.catalog where schema = 'myschema';

