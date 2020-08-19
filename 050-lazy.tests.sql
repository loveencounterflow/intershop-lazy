

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
drop schema if exists MYSCHEMA cascade; create schema MYSCHEMA;



-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 3 }———:reset
create view MYSCHEMA.products as ( select
      ( key->0 )::integer as n,
      ( key->1 )::integer as factor,
      ( value  )::integer as product
    from LAZY.facets
    where bucket = 'MYSCHEMA.products' );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 4 }———:reset
create function MYSCHEMA._get_product_key( ¶n integer, ¶factor integer )
  returns jsonb immutable strict language sql as $$ select ( format( '[%s,%s]', ¶n, ¶factor ) )::jsonb; $$;

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 5 }———:reset
-- ### NOTE consider to allow variant where update method returns key, value instead of inserting itself;
-- the latter is more general as it may insert an arbitrary number of adjacent / related / whatever items
create function MYSCHEMA._update_products_cache( ¶n integer, ¶factor integer )
  returns void volatile strict language plpgsql as $$ declare
    ¶bucket text  :=  'MYSCHEMA.products';
    ¶key    jsonb :=  MYSCHEMA._get_product_key( ¶n, ¶factor );
  begin
    if ¶n != 13 then
      insert into LAZY.facets ( bucket, key, value ) values ( ¶bucket, ¶key, to_jsonb( ¶n * ¶factor ) );
    else
      if ( ¶factor % 2 ) = 0 then
        insert into LAZY.facets ( bucket, key, value ) values ( ¶bucket, ¶key, null );
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
    ¶value := ( select value from LAZY.facets where bucket = ¶bucket and ¶key = key );
    if ¶value is not null then return ¶value::integer; end if;
    perform MYSCHEMA._update_products_cache( ¶n, ¶factor );
    ¶value := ( select value from LAZY.facets where bucket = ¶bucket and ¶key = key );
    if ¶value is not null then return ¶value::integer; end if;
    raise sqlstate 'XXX02' using message = format( '#XXX02-1 Key Error: unable to retrieve result for ¶n: %s, ¶factor: %s', ¶n, ¶factor );
    end; $$;

-- select * from CATALOG.catalog where schema = 'lazy';
select LAZY.create_lazy_function(
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

select LAZY.create_lazy_function(
  function_name   => 'MYSCHEMA.get_product_2',          -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  bucket          => null,                              -- optional, defaults to `function_name`
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => '¶n * ¶factor',                    -- optional, this x-or `perform_update` must be given
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => 'cast_my_value'                    -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  );

select * from LAZY.facets order by bucket, key;
select * from MYSCHEMA.get_product_1( 4, 12 );
select * from MYSCHEMA.get_product_1( 5, 12 );
select * from MYSCHEMA.get_product_1( 6, 12 );
select * from LAZY.facets order by bucket, key;
select * from MYSCHEMA.products;
select * from MYSCHEMA.get_product_1( 13, 12 );

/* ###################################################################################################### */
\echo :red ———{ :filename 22 }———:reset
\quit



-- =========================================================================================================
--
-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
create table LAZY_X.probes_and_matchers_1 (
  title     text,
  probe     text,
  matcher   text,
  result    text );

create table LAZY_X.probes_and_matchers_2 (
  title     text,
  probe_1   text,
  probe_2   text,
  matcher   text,
  result    text );

-- select ( '{}'::jsonb )->'x';
-- select pg_typeof( ( '{}'::jsonb )->'x' );

-- ---------------------------------------------------------------------------------------------------------
\echo :signal ———{ :filename 1 }———:reset
insert into LAZY_X.probes_and_matchers_1 ( title, probe, matcher ) values
  ( 'escape_text',               'helo',         'helo'                      ),
  ( 'escape_text',               'helo>>>world', 'helo&gt;&gt;&gt;world'     ),
  ( 'escape_text',               '<13&14>',      '&lt;13&amp;14&gt;'         ),
  ( 'escape_text',               '<helo',        '&lt;helo'                  ),
  ( 'as_attributes',             '{"foo":"bar"}', 'foo=''bar'''                  ),
  ( 'as_attributes',             '{"foo":"bar","height":33}', 'foo=''bar'' height=''33'''                  ),
  ( 'tag', '{"$key":"<tag","name":"div","atrs":{"width":25,"height":120}}',              '<div width=''25'' height=''120''>'        ),
  ( 'tag', '{"$key":">tag","name":"div","atrs":{"width":25,"height":120}}',              '</div>'                                   ),
  ( 'tag', '{"$key":"^tag","name":"div","atrs":{"width":25,"height":120}}',              '<div width=''25'' height=''120''></div>'  ),
  ( 'tag', '{"$key":"^tag","name":"div","short":true,"atrs":{"width":25,"height":120}}', '<div width=''25'' height=''120''/>'       ),
  ( 'tag', '{"$key":"<tag","name":"div"}',                                               '<div>'                                    ),
  ( 'tag', '{"$key":">tag","name":"div"}',                                               '</div>'                                   ),
  ( 'tag', '{"$key":"^tag","name":"div"}',                                               '<div></div>'                              ),
  ( 'tag', '{"$key":"^tag","name":"div","short":true}',                                  '<div/>'                                   ),
  ( 'escape_attribute_value', '<"helo">',        '''&lt;"helo"&gt;'''                  ),
  ( 'escape_attribute_value', '<''helo''>',      '''&lt;&#39;helo&#39;&gt;'''                  );
update LAZY_X.probes_and_matchers_1 set result = LAZY.escape_text( probe ) where title = 'escape_text';
update LAZY_X.probes_and_matchers_1 set result = LAZY.escape_attribute_value( probe ) where title = 'escape_attribute_value';
update LAZY_X.probes_and_matchers_1 set result = LAZY.as_attributes( probe::jsonb ) where title = 'as_attributes';
update LAZY_X.probes_and_matchers_1 set result = LAZY.tag( probe::jsonb ) where title = 'tag';

insert into LAZY_X.probes_and_matchers_2 ( title, probe_1, probe_2, matcher ) values
  ( 'as_attribute', 'width', '25',    'width=''25'''                  );
update LAZY_X.probes_and_matchers_2 set result = LAZY.as_attribute( probe_1, probe_2 ) where title = 'as_attribute';

-- ---------------------------------------------------------------------------------------------------------
insert into INVARIANTS.tests select
    'LAZY'                                           as module,
    r1.title                                        as title,
    row( result, matcher )::text                    as values,
    ( r1.result = r1.matcher )                      as is_ok
  from LAZY_X.probes_and_matchers_1 as r1;

-- ---------------------------------------------------------------------------------------------------------
insert into INVARIANTS.tests select
    'LAZY'                                           as module,
    r1.title                                        as title,
    row( result, matcher )::text                    as values,
    ( r1.result = r1.matcher )                      as is_ok
  from LAZY_X.probes_and_matchers_1 as r1;

select * from LAZY_X.probes_and_matchers_1;
select * from INVARIANTS.tests;
select * from INVARIANTS.violations;
-- select count(*) from ( select * from INVARIANTS.violations limit 1 ) as x;
-- select count(*) from INVARIANTS.violations;
do $$ begin perform INVARIANTS.validate(); end; $$;

( select LAZY.tag( '{"$key":"<tag","name":"div","atrs":{"width":25,"height":120}}'::jsonb ) ) union all
( select LAZY.tag( '{"$key":">tag","name":"div","atrs":{"width":25,"height":120}}'::jsonb ) ) union all
( select LAZY.tag( '{"$key":"^tag","name":"div","atrs":{"width":25,"height":120}}'::jsonb ) ) union all
( select LAZY.tag( '{"$key":"^tag","name":"div","short":true,"atrs":{"width":25,"height":120}}'::jsonb ) ) union all
( select null where false );


/* ###################################################################################################### */
\echo :red ———{ :filename 7 }———:reset
\quit




-- do $$ begin perform INVARIANTS.validate(); end; $$;

-- -- instead.








