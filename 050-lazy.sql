
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
create table LAZY.facets (
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
create function LAZY._normalize( LAZY.facets ) returns LAZY.facets immutable language sql as
  $$ select
    case when ( $1.value.error is distinct from null )
      then ( $1.bucket, $1.key, ( null::jsonb, $1.value.error ) )::LAZY.facets
      else ( $1.bucket, $1.key, LAZY._normalize( $1.value ) )::LAZY.facets end; $$;

comment on function LAZY._normalize( LAZY.jsonb_result ) is 'Given a `LAZY.jsonb_result` value or `null`,
return a LAZY.jsonb_result value with all three fields set to null if either the value is `null`, or its
`ok` field is `null` or JSONB `''null''`; otherwise, return the value itself.';


-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create function LAZY.on_before_update_facets() returns trigger language plpgsql as $$ begin
  raise sqlstate 'LZ104' using message = format( 'illegal to update LAZY.facets' ); end; $$;
create trigger on_before_update_facets before update on LAZY.facets
  for each row execute procedure LAZY.on_before_update_facets();

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create function LAZY.on_before_insert_facets() returns trigger language plpgsql as $$ begin
  return LAZY._normalize( new ); end; $$;
create trigger on_before_insert_facets before insert on LAZY.facets
  for each row execute procedure LAZY.on_before_insert_facets();


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
      ¶k := format( 'jsonb_build_array( %s )', ¶n );
    else
      ¶k := format( '%s( %s )', get_key, ¶n );
      end if;
    -- .....................................................................................................
    ¶bucket :=  coalesce( bucket, function_name );
    ¶v      :=  format( '%s( ¶value )::%s', coalesce( caster, '' ), return_type );
    -- .....................................................................................................
    if ( get_update is null ) and ( perform_update is null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be non-null'; end if;
    if ( get_update is not null ) and ( perform_update is not null ) then
      raise sqlstate 'LZ120' using message =
      '#LZ120 Type Error: one of get_update, perform_update must be null'; end if;
    -- .....................................................................................................
    R  := '';
    R  := R  || format( e'create function %s( %s )                                  \n', function_name, ¶p );
    R  := R  || format( e'  returns %s strict volatile language plpgsql as $f$      \n', return_type );
    R  := R  ||         e'  declare                                                 \n';
    R  := R  || format( e'    ¶key    jsonb := %s;                                  \n', ¶k );
    R  := R  ||         e'    ¶value  jsonb;                                        \n';
    R  := R  ||         e'  begin                                                   \n';
    -- .....................................................................................................
    ¶r := '';
    ¶r := ¶r ||         e'  -- ---------------------------------------------------\n';
    ¶r := ¶r ||         e'  ¶value := ( select value from LAZY.facets             \n';
    ¶r := ¶r || format( e'    where bucket = %L and key = ¶key );                 \n', ¶bucket );
    ¶r := ¶r || format( e'  if ¶value is not null then return %s; end if;         \n', ¶v );
    R  := R  || ¶r;
    -- .....................................................................................................
    R  := R  ||         e'  -- -----------------------------------------------------\n';
    if ( get_update is not null ) then
      R  := R  || format( e'  ¶value := %s;\n', get_update );
      R  := R  ||         e'  insert into LAZY.facets ( bucket, key, value ) values \n';
      R  := R  || format( e'    ( %L, ¶key, to_jsonb( ¶value ) );                   \n', ¶bucket );
      R  := R  || format( e'  if ¶value is not null then return ¶value::%s; end if; \n', return_type );
    else
      R  := R  || format( e'  perform %s( %s );                                     \n', perform_update, ¶n );
      R  := R  || ¶r;
      end if;
    -- .....................................................................................................
    R  := R  ||         e'  -- -----------------------------------------------------\n';
    R  := R  ||         e'  raise sqlstate ''LZ120'' using                          \n';
    R  := R  ||         e'    message = format( ''#LZ120 Key Error: '' ||           \n';
    R  := R  || format( e'    ''unable to retrieve result for %s'', %s );           \n', ¶x, ¶n );
    R  := R  ||         e'  end; $f$;';
    -- .....................................................................................................
    return R;
  end; $outer$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 9 }———:reset
-- ### TAINT could/should be procedure? ###
create function LAZY.create_lazy_function(
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
    execute LAZY._create_lazy_function(
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
\echo :red ———{ :filename 22 }———:reset
\quit


-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 10 }———:reset

-- select * from MYSCHEMA.products order by n, factor;
-- select * from MYSCHEMA.get_product( 13, 12 );
-- select * from MYSCHEMA.products order by n, factor;
-- -- select * from MYSCHEMA.get_product( 13, 13 );

-- select * from LAZY.create_lazy_function(
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



