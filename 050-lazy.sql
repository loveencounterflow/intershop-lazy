
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
\echo :signal ———{ :filename 2 }———:reset
create type LAZY.jsonb_result as (
  ok          jsonb,
  error       text );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create table LAZY.cache (
  bucket        text              not null,
  key           jsonb             not null,
  value         LAZY.jsonb_result not null,
  primary key ( bucket, key ) );

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.is_happy( LAZY.jsonb_result ) returns boolean immutable strict language sql as
  $$ select ( $1.error is null ); $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.is_sad( LAZY.jsonb_result ) returns boolean immutable strict language sql as
  $$ select ( $1.error is not null ); $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.happy( ok jsonb ) returns LAZY.jsonb_result immutable strict language sql as
  $$ select ( ok, null )::LAZY.jsonb_result; $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.happy( ok anyelement ) returns LAZY.jsonb_result immutable strict language sql as
  $$ select ( to_jsonb( ok ), null )::LAZY.jsonb_result; $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.sad( error text ) returns LAZY.jsonb_result immutable strict language sql as
  $$ select ( null, error )::LAZY.jsonb_result; $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY.unwrap( LAZY.jsonb_result )
  returns jsonb immutable strict language plpgsql as $$
  declare
    ¶error  text;
  begin
    if LAZY.is_happy( $1 ) then return $1.ok; end if;
    ¶error  := coalesce( $1.error, 'an unspecified error occurred during a lazy value retrieval' );
    ¶error  := 'LZE00' || ' ' || ¶error;
    raise sqlstate 'LZE00' using message = ¶error;
    end; $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY._normalize( LAZY.jsonb_result ) returns LAZY.jsonb_result immutable language sql as
  $$ select
    case when ( $1 is not distinct from null ) or ( $1.ok = 'null'::jsonb )
      then ( null::jsonb, null )::LAZY.jsonb_result
      else $1 end; $$;

-- ---------------------------------------------------------------------------------------------------------
create function LAZY._normalize( LAZY.cache ) returns LAZY.cache immutable language sql as
  $$ select
    case when ( $1.value.error is distinct from null )
      then ( $1.bucket, $1.key, ( null::jsonb, $1.value.error ) )::LAZY.cache
      else ( $1.bucket, $1.key, LAZY._normalize( $1.value ) )::LAZY.cache end; $$;

comment on function LAZY._normalize( LAZY.jsonb_result ) is 'Given a `LAZY.jsonb_result` value or `null`,
return a LAZY.jsonb_result value with all three fields set to null if either the value is `null`, or its
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
  return LAZY._normalize( new ); end; $$;
create trigger on_before_insert_cache before insert on LAZY.cache
  for each row execute procedure LAZY.on_before_insert_cache();


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 4 }———:reset
-- ### TAINT could/should be procedure? ###
create function LAZY._create_lazy_producer(
  function_name     text,
  parameter_names   text[],
  parameter_types   text[],
  return_type       text,
  bucket            text default null,
  get_key           text default null,
  get_update        text default null,
  perform_update    text default null,
  caster            text default null )
  returns text immutable called on null input language plpgsql as $outer$
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
      ¶v      :=  format( e'%s( LAZY.unwrap( ¶value ) )::%s', coalesce( caster, '' ), return_type );
    else
      ¶v      :=  format( e'%s( LAZY.unwrap( ¶rows[ 1 ] ) )::%s', coalesce( caster, '' ), return_type );
      end if;
    -- .....................................................................................................
    if ( get_update is null ) and ( perform_update is null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be non-null'; end if;
    if ( get_update is not null ) and ( perform_update is not null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be null'; end if;
    -- .....................................................................................................
    R  := '';
    R  := R  || format( e'/*^1^*/ create function %s( %s )'                                   || e'\n', function_name, ¶p );
    R  := R  || format( e'/*^2^*/   returns %s'                                               || e'\n', return_type );
    R  := R  ||         e'/*^3^*/   called on null input volatile language plpgsql as $f$'    || e'\n';
    R  := R  ||         e'/*^4^*/   declare'                                                  || e'\n';
    R  := R  || format( e'/*^5^*/     ¶key    jsonb := %s;'                                   || e'\n', ¶k );
    R  := R  ||         e'/*^6^*/     ¶rows   LAZY.jsonb_result[];'                           || e'\n';
    R  := R  ||         e'/*^7^*/     ¶value  LAZY.jsonb_result;'                             || e'\n';
    R  := R  ||         e'/*^8^*/   begin'                                                    || e'\n';
    -- .....................................................................................................
    ¶r := '';
    ¶r := ¶r ||         e'/*^9^*/   -- ---------------------------------------------------'   || e'\n';
    ¶r := ¶r ||         e'/*^10^*/   ¶rows := ( select array_agg( value ) from LAZY.cache'   || e'\n';
    ¶r := ¶r || format( e'/*^11^*/    where bucket = %L and key = ¶key );'                    || e'\n', ¶bucket );
    ¶r := ¶r ||         e'/*^12^*/  if array_length( ¶rows, 1 ) = 1 then'                     || e'\n';
    ¶r := ¶r || format( e'/*^13^*/    return %s; end if;'                                     || e'\n', ¶v );
    R  := R  || ¶r;
    -- .....................................................................................................
    R  := R  ||         e'/*^18^*/  -- -----------------------------------------------------' || e'\n';
    if ( get_update is not null ) then
      R  := R  || format( e'/*^19^*/  ¶value := %s( %s );'                                      || e'\n', get_update, ¶n );
      R  := R  ||         e'/*^20^*/  insert into LAZY.cache ( bucket, key, value ) values'    || e'\n';
      R  := R  || format( e'/*^21^*/    ( %L, ¶key, ¶value );'                                  || e'\n', ¶bucket );
      R  := R  || format( e'/*^22^*/    return %s;'                                             || e'\n', ¶v );
    else
      R  := R  || format( e'/*^23^*/  perform %s( %s );'                                        || e'\n', perform_update, ¶n );
      R  := R  || ¶r;
      R  := R  ||         e'/*^14^*/  ¶value := null::LAZY.jsonb_result;'                       || e'\n';
      R  := R  ||         e'/*^15^*/  insert into LAZY.cache ( bucket, key, value ) values'    || e'\n';
      R  := R  || format( e'/*^16^*/    ( %L, ¶key, ¶value );'                                  || e'\n', ¶bucket );
      R  := R  || format( e'/*^17^*/    return %s;'                                             || e'\n', ¶v );
      end if;
    -- -- .....................................................................................................
    R  := R  ||         e'/*^28^*/  end; $f$;';
    -- .....................................................................................................
    return R;
  end; $outer$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
-- ### TAINT could/should be procedure? ###
create function LAZY.create_lazy_producer(
  function_name     text,
  parameter_names   text[],
  parameter_types   text[],
  return_type       text,
  bucket            text default null,
  get_key           text default null,
  get_update        text default null,
  perform_update    text default null,
  caster            text default null )
  returns void volatile called on null input language plpgsql as $$
    begin
    execute LAZY._create_lazy_producer(
      function_name   => function_name,
      parameter_names => parameter_names,
      parameter_types => parameter_types,
      return_type     => return_type,
      bucket          => bucket,
      get_key         => get_key,
      get_update      => get_update,
      perform_update  => perform_update,
      caster          => caster );
      end; $$;

/* ###################################################################################################### */
\echo :red ———{ :filename 6 }———:reset
\quit


-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 7 }———:reset

-- select * from MYSCHEMA.products order by n, factor;
-- select * from MYSCHEMA.get_product( 13, 12 );
-- select * from MYSCHEMA.products order by n, factor;
-- -- select * from MYSCHEMA.get_product( 13, 13 );

-- select * from LAZY.create_lazy_producer(
--   'cache', 'get_product_generated',
--   array[ array[ '¶n', 'integer' ], array[ '¶factor', 'integer' ] ],
--   'r.result',
--   'integer',
--   'n = ¶n and factor = ¶factor',
--   'r.result is not null'
--   );

-- select * from MYSCHEMA.products order by n, factor;
-- select * from MYSCHEMA.get_product_generated( 4, 12 );
-- select * from MYSCHEMA.products order by n, factor;
-- select * from MYSCHEMA.get_product_generated( 13, 12 );
-- select * from MYSCHEMA.get_product_generated( 13, 14 );
-- select * from MYSCHEMA.get_product_generated( 144, 144 );
-- select * from MYSCHEMA.products order by n, factor;
-- select * from MYSCHEMA.get_product_generated( 13, 13 );



