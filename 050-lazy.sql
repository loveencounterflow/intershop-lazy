
-- \set ECHO queries
begin transaction;

/* ###################################################################################################### */
\ir './_trm.sql'
-- \ir './set-signal-color.sql'
-- \ir './test-begin.sql'
-- \pset pager on
\timing off
-- ---------------------------------------------------------------------------------------------------------
\set filename intershop-lazy/050-lazy.sql
\set signal :blue

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
drop schema if exists LAZY cascade; create schema LAZY;


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create table LAZY.cache (
  bucket        text              not null,
  key           jsonb             not null,
  value         jsonb,
  primary key ( bucket, key ) );

-- ---------------------------------------------------------------------------------------------------------
create function LAZY._normalize( jsonb ) returns jsonb immutable language sql as $$ select
  case when ( $1 = 'null'::jsonb ) then null::jsonb else $1 end; $$;

comment on function LAZY._normalize( jsonb ) is 'Given a `jsonb` value or `null`,
return a jsonb value with all three fields set to null if either the value is `null`, or its
`ok` field is `null` or JSONB `''null''`; otherwise, return the value itself.';


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create function LAZY.on_before_update_cache() returns trigger language plpgsql as $$ begin
  raise sqlstate 'LZ104' using message = format( 'illegal to update LAZY.cache' ); end; $$;
create trigger on_before_update_cache before update on LAZY.cache
  for each row execute procedure LAZY.on_before_update_cache();

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create function LAZY.on_before_insert_cache() returns trigger language plpgsql as $$ begin
  return ( new.bucket, new.key, LAZY._normalize( new.value ) )::LAZY.cache; end; $$;
create trigger on_before_insert_cache before insert on LAZY.cache
  for each row execute procedure LAZY.on_before_insert_cache();


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 4 }———:reset
-- ### TAINT could/should be procedure? ###
create function LAZY.create_lazy_producer(
  function_name     text,
  parameter_names   text[],
  parameter_types   text[],
  return_type       text,
  bucket            text default null,
  get_key           text default null,
  get_update        text default null,
  perform_update    text default null )
  returns text volatile called on null input language plpgsql as $outer$
  declare
    ¶bucket text;
    ¶p      text;
    ¶k      text;
    ¶n      text;
    ¶v      text;
    ¶r      text;
    ¶u      text;
    ¶x      text;
    R       text;
    -- ¶z      text;
    -- ¶q      text;
  begin
    -- .....................................................................................................
    if ( get_update is null ) and ( perform_update is null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be non-null'; end if;
    if ( get_update is not null ) and ( perform_update is not null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be null'; end if;
    -- .....................................................................................................
    -- ### TAINT validate both arrays have at least one element, same number of elements
    ¶p := ( select string_agg( format( '%s %s', name, parameter_types[ r1.nr ] ), ', ' )
      from unnest( parameter_names ) with ordinality as r1 ( name, nr ) );
    ¶n := ( select string_agg( n, ', ' ) from unnest( parameter_names ) as x ( n ) );
    ¶x := ( select string_agg( n || ': %s', ', ' ) from unnest( parameter_names ) as x ( n ) );
    -- .....................................................................................................
    if get_key is null then
      ¶k := format( e'jsonb_build_array( %s )', ¶n );
    else
      ¶k := format( e'%s( %s )', get_key, ¶n );
      end if;
    -- .....................................................................................................
    ¶bucket :=  coalesce( bucket, function_name );
    if ( get_update is not null ) then
      ¶v      :=  format( e'( ¶value )::%s', return_type );
    else
      ¶v      :=  format( e'( ¶rows[ 1 ] )::%s', return_type );
      end if;
    -- .....................................................................................................
    R  := '';
    R  := R  || format( e'/*^1^*/ create function %s( %s )'                                   || e'\n', function_name, ¶p );
    R  := R  || format( e'/*^2^*/   returns %s'                                               || e'\n', return_type );
    R  := R  ||         e'/*^3^*/   called on null input volatile language plpgsql as $f$'    || e'\n';
    R  := R  ||         e'/*^4^*/   declare'                                                  || e'\n';
    R  := R  || format( e'/*^5^*/     ¶key    jsonb := %s;'                                   || e'\n', ¶k );
    R  := R  ||         e'/*^6^*/     ¶rows   jsonb[];'                                       || e'\n';
    R  := R  ||         e'/*^7^*/     ¶value  jsonb;'                                         || e'\n';
    R  := R  ||         e'/*^8^*/   begin'                                                    || e'\n';
    -- .....................................................................................................
    ¶r := '';
    ¶r := ¶r ||         e'/*^9^*/   -- ---------------------------------------------------'   || e'\n';
    ¶r := ¶r ||         e'/*^10^*/   -- Try to retrieve and return value from cache:'          || e'\n';
    ¶r := ¶r ||         e'/*^11^*/   ¶rows := ( select array_agg( value ) from LAZY.cache'    || e'\n';
    ¶r := ¶r || format( e'/*^12^*/    where bucket = %L and key = ¶key );'                    || e'\n', ¶bucket );
    ¶r := ¶r ||         e'/*^13^*/  if array_length( ¶rows, 1 ) = 1 then'                     || e'\n';
    ¶r := ¶r || format( e'/*^14^*/    return %s; end if;'                                     || e'\n', ¶v );
    ¶r := ¶r ||         e'/*^15^*/  ¶value := null::jsonb;'                                   || e'\n';
    R  := R  || ¶r;
    -- .....................................................................................................
    R  := R  ||         e'/*^16^*/  -- -----------------------------------------------------' || e'\n';
    if ( get_update is not null ) then
      R  := R  ||         e'/*^17^*/  -- Compute value and put it into cache:'                  || e'\n';
      R  := R  || format( e'/*^18^*/  ¶value := %s( %s );'                                      || e'\n', get_update, ¶n );
      R  := R  ||         e'/*^19^*/  insert into LAZY.cache ( bucket, key, value ) values'     || e'\n';
      R  := R  || format( e'/*^20^*/    ( %L, ¶key, ¶value );'                                  || e'\n', ¶bucket );
      R  := R  || format( e'/*^21^*/    return %s;'                                             || e'\n', ¶v );
    else
      R  := R  || format( e'/*^22^*/  perform %s( %s );'                                        || e'\n', perform_update, ¶n );
      R  := R  || ¶r;
      R  := R  ||         e'/*^23^*/  insert into LAZY.cache ( bucket, key, value ) values'     || e'\n';
      R  := R  || format( e'/*^24^*/    ( %L, ¶key, ¶value );'                                  || e'\n', ¶bucket );
      R  := R  || format( e'/*^25^*/    return %s;'                                             || e'\n', ¶v );
      end if;
    -- -- .....................................................................................................
    R  := R  ||         e'/*^26^*/  end; $f$;';
    -- .....................................................................................................
    execute R;
    return R;
  end; $outer$;


/* ###################################################################################################### */
\echo :red ———{ :filename 6 }———:reset
\quit



