

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
create type NLEX.number_type as enum ( 'ordinal', 'cardinal' );
create type NLEX.number_words as (
  number      numeric,
  type        NLEX.number_type,
  language    text,
  word        text );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create view NLEX.lexicon as ( select
      ( ( key->>0 )::numeric  ) as number,
      ( key->>1               ) as type,
      ( key->>2               ) as language,
      ( value::text           ) as word
    from LAZY.cache
    where bucket = 'numericlexicon'
    order by language, number, type );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
create function NLEX.insert_number_word( ¶number numeric, ¶type NLEX.number_type, ¶language text )
  returns void volatile called on null input language plpgsql as $$
  declare
    ¶word text;
  begin
    case ¶language
      -- ...................................................................................................
      when 'en' then
        case ¶type
          when 'ordinal' then
            case
              when ¶number < 1 then ¶word = 'zeroth';
              when ¶number = 3 then ¶word = 'third';
              else ¶word = 'nth'; end case;
          else
            case
              when ¶number < 1 then ¶word = 'small';
              when ¶number = 3 then ¶word = 'three';
              else ¶word = 'big'; end case;
          end case;
      -- ...................................................................................................
      when 'de' then
        case ¶type
          when 'ordinal' then
            case
              when ¶number < 1 then ¶word = 'nullter';
              when ¶number = 3 then ¶word = 'dritter';
              else ¶word = 'nter'; end case;
          else
            case
              when ¶number < 1 then ¶word = 'klein';
              when ¶number = 3 then ¶word = 'drei';
              else ¶word = 'gross'; end case;
          end case;
      else
        ¶word := null;
        end case;
    raise notice using message = format( '^3334^ %L <- insert_number_word( %L, %L, %L )',
      ¶word, ¶number, ¶type, ¶language );
    insert into LAZY.cache ( bucket, key, value ) values
      ( 'numericlexicon', jsonb_build_array( ¶number, ¶type, ¶language ), ¶word );
    end; $$;


-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
select LAZY.create_lazy_producer(
  function_name   => 'NLEX.get_number_word',
  parameter_names => '{¶number,¶type,¶language}',
  parameter_types => '{numeric,NLEX.number_type,text}',
  return_type     => 'text',
  bucket          => 'numericlexicon',
  perform_update  => 'NLEX.insert_number_word' );

create view NLEX.inputs as
  ( select null::numeric as n, null::NLEX.number_type as type, null::text as language where false ) union all
values
  ( 3, 'cardinal'::NLEX.number_type, 'de' ),
  ( 3, 'cardinal'::NLEX.number_type, 'en' ),
  ( 3, 'ordinal'::NLEX.number_type, 'de' ),
  ( 3, 'ordinal'::NLEX.number_type, 'en' );

select * from NLEX.inputs;

select
    *
  from NLEX.inputs                                            as r1 ( n, type, language ),
  lateral NLEX.get_number_word( r1.n, r1.type, r1.language )  as r2;
\echo :reverse:steel' LAZY.cache '
select * from LAZY.cache;
\echo :reverse:steel' NLEX.lexicon '
select * from NLEX.lexicon;


/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit


select * from CATALOG.catalog where schema = 'myschema';

