# InterShop Lazy

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

  - [Purpose](#purpose)
  - [Value Producers](#value-producers)
- [API](#api)
  - [Methods to Create Lazy Value Producers](#methods-to-create-lazy-value-producers)
  - [Helper Methods](#helper-methods)
- [Complete Demo](#complete-demo)
  - [Demo I: Multiplying Integers](#demo-i-multiplying-integers)
    - [Step 1: Write an Eager Value Producer](#step-1-write-an-eager-value-producer)
    - [Step 2: Create a Lazy Producer](#step-2-create-a-lazy-producer)
    - [Step 3: Use the Lazy Value Producer](#step-3-use-the-lazy-value-producer)
  - [DEMO II: Summing Up, Speculatively](#demo-ii-summing-up-speculatively)
    - [Step 1: Write a Speculative Eager Value Producer](#step-1-write-a-speculative-eager-value-producer)
    - [Step 2: Create a Lazy Producer](#step-2-create-a-lazy-producer-1)
    - [Step 3: Use the Lazy Value Producer](#step-3-use-the-lazy-value-producer-1)
  - [Bonus: Setting up Custom Cache Views](#bonus-setting-up-custom-cache-views)
- [Updates](#updates)
- [To Do](#to-do)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Purpose

InterShop Lazy provides a way to (almost) transparently store results of costly computations in a table for
later retrieval.

* Lazy value producer:
* Eager value producer: function working in the background that returns values to be inserted into the cache
  or that inserts values into the cache itself.



## Value Producers

Value producers are assumed to be 'immutable' functions in the PostGreSQL sense, i.e. 'pure functions' in
the functional sense.

# API

## Methods to Create Lazy Value Producers

`LAZY.create_lazy_producer()` (`returns void`) will create a function that uses table `LAZY.cache` to
produce values in a lazy fashion. Its arguments are:

* **`function_name`** (**`text`**)—name of function to be created.
* **`parameter_names`** (**`text[]`**)—names of arguments to the getter.
* **`parameter_types`** (**`text[]`**)—types of arguments to the getter.
* **`return_type`** (**`text,`**)—applied to jsonb value.
* **`bucket`** (**`text default null`**)—name of bucket; defaults to `function_name`.
* **`get_key`** (**`text default null`**)—optional, default is JSON list / object of values.
* **`get_update`** (**`text default null`**)—optional, this x-or `perform_update` must be given.
* **`perform_update`** (**`text default null`**)—optional, this x-or `get_update` must be given.

Points to keep in mind:

* All names used in calls to `create_lazy_producer()` will be used as-is without any kind of sanity check or
  quoting.
* The same goes for the other arguments.
* Usage of `create_lazy_producer()` is inherently unsafe; therefore, no untrusted data (such as coming from
  a web form as data source) should be used to call this function (although the function that
  `create_lazy_producer()` creates is itself deemed safe).

## Helper Methods

* **`LAZY.nullify( jsonb ) returns jsonb`**—Given `null` or any `jsonb` value, return `null` when the input
  is `null` or `'null'::jsonb` (i.e. the `null` value of JSONB, *which is distinct from SQL null*), or the
  value itself otherwise. This method helps to prevent errors like `cannot cast jsonb null to type x`:
  instead of `( key->0 )::integer`, write `( LAZY.nullify( key->0 ) )::integer` to obtain SQL `null` for
  cases where a (subvalue of a) cache column might contain `null` values.


# Complete Demo

> The below code can be seen in action by running `psql -f lazy.demo-1.sql` and `psql -f lazy.demo-2.sql`.

In this demo, we want to write two lazy value producers that compute multiples of floats and sums of
integers; for the first, we will use an eager value getter that will only procude one value per call; for
the sums, we will have a look at an eager value inserter that guesses values that might be used in the
future and inserts them into the cache table for later use. Additionally, we will set up custom cache views
that make read-only access to cached values easier than looking at the cache table directly. So let's get
started.

## Demo I: Multiplying Integers

### Step 1: Write an Eager Value Producer

The first thing to do when one wants to use lazy evaluation with InterShop Lazy is to provide a function
that accepts arguments as required for the task at hand and that returns a value `v` of type `T` that will
be serialized `v::text` and deserialized as `v::T`.

Of course, using lazy evaluation makes only sense when one is dealing with costly computations, so typically
an eager value producer would involve stuff like network access, sifting through huge tables or maybe
reading in data files, that kind of IO- or CPU-heavy stuff. To keep things simple, let's just multiply
integers and throw in the quirk that multiples of `13` will produce `null` values for no obvious reason. For
good measure, we also want to report any calls to the console which is what the `raise notice` statement is
for:

```sql
create function MYSCHEMA.compute_product( ¶n float, ¶factor float )
  returns float immutable called on null input language plpgsql as $$ begin
    raise notice 'MYSCHEMA.compute_product( %, % )', ¶n, ¶factor;
    if ( ¶n is null ) or ( ¶factor is null ) then return 0; end if;
    if ¶n != 13 then return ¶n * ¶factor; end if;
    return null; end; $$;
```

This function is called an eager value producer because it is expected to actually compute a result for each
time it gets called. Observe we have defined it as `immutable called on null input`, meaning that it will be
called even if one of its arguments is `null`; this we exploit to return `0` as the product whenever one of
the factors is SQL `null`. Had we used `strict` instead, PostGreSQL would have eschewed calling the function
at all and filled in a `null`, which may or may not be what you want.


### Step 2: Create a Lazy Producer

Now that we have an eager value producer, let's define a lazy value producer that uses results from the
`LAZY.cache` table where possible and manages updating it where values are missing. To do this, we have to
call `LAZY.create_lazy_producer()`:

```sql
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product',
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{float,float}',
  return_type     => 'float',
  get_update      => 'MYSCHEMA.compute_product' );
```

Observe that the `select` statement will both create `MYSCHEMA.get_product()` and return the source text for
that new function, which may end up in the console or wherever your SQL output goes, so you might want to
use `do $$ begin perform LAZY.create_lazy_producer( ... ); end; $$;` instead.

The first argument here is the name of the new function to be created; the next 3 arguments basically repeat
the declarative part to that function (a future version of InterShop Lazy might auto-generate
`parameter_names`, `parameter_types` and `return_type`).

There's just one more required argument, either `get_update` or `perform_update`; exactly one of these two
must be set to the name of a function that either

* in the case of `get_update()`, will return exactly one result for each set of inputs, or
* in the case of `perform_update()`, may insert as many rows into `LAZY.cache` as seen fit when called. In
  case `perform_update()` happened to not produce a result line that matches the input arguments, a line
  with result `null` will be auto-generated.

### Step 3: Use the Lazy Value Producer

We're now ready to put our caching, lazy multiplicator device to use. For this, we set up a table
of factors and update it with the computation results:

```sql
create table MYSCHEMA.fancy_products (
  n         float,
  factor    float,
  result    float );

insert into MYSCHEMA.fancy_products ( n, factor ) values
  ( 123,  456  ),
  ( 4,    12   ),
  ( 5,    12   ),
  ( 6,    12   ),
  ( 6,    12   ),
  ( 6,    12   ),
  ( 6,    12   ),
  ( 6,    12   ),
  ( 6.3,  12   ),
  ( 60,   3    ),
  ( 13,   13   ),
  ( 1,    null ),
  ( null, null ),
  ( null, 100  );

update MYSCHEMA.fancy_products set result = MYSCHEMA.get_product( n, factor );
select * from MYSCHEMA.fancy_products order by n, factor;
select * from LAZY.cache order by bucket, key;
```

This will produce the following output:

```
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 123, 456 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 4, 12 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 5, 12 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 6, 12 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 6.3, 12 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 60, 3 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 13, 13 )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( 1, <NULL> )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( <NULL>, <NULL> )
psql:lazy.demo-1.sql:76: NOTICE:  MYSCHEMA.compute_product( <NULL>, 100 )
╔═════╤════════╤════════╗
║  n  │ factor │ result ║
╠═════╪════════╪════════╣
║   1 │      ∎ │      0 ║
║   4 │     12 │     48 ║
║   5 │     12 │     60 ║
║   6 │     12 │      ∎ ║
║   6 │     12 │      ∎ ║
║   6 │     12 │      ∎ ║
║   6 │     12 │     72 ║
║   6 │     12 │      ∎ ║
║ 6.3 │     12 │   75.6 ║
║  13 │     13 │      ∎ ║
║  60 │      3 │    180 ║
║ 123 │    456 │  56088 ║
║   ∎ │    100 │      0 ║
║   ∎ │      ∎ │      0 ║
╚═════╧════════╧════════╝

╔══════════════════════╤══════════════╤═══════╗
║        bucket        │     key      │ value ║
╠══════════════════════╪══════════════╪═══════╣
║ MYSCHEMA.get_product │ [null, null] │ 0     ║
║ MYSCHEMA.get_product │ [null, 100]  │ 0     ║
║ MYSCHEMA.get_product │ [1, null]    │ 0     ║
║ MYSCHEMA.get_product │ [4, 12]      │ 48    ║
║ MYSCHEMA.get_product │ [5, 12]      │ 60    ║
║ MYSCHEMA.get_product │ [6, 12]      │ 72    ║
║ MYSCHEMA.get_product │ [6.3, 12]    │ 75.6  ║
║ MYSCHEMA.get_product │ [13, 13]     │ ∎     ║
║ MYSCHEMA.get_product │ [60, 3]      │ 180   ║
║ MYSCHEMA.get_product │ [123, 456]   │ 56088 ║
╚══════════════════════╧══════════════╧═══════╝
```

The above shows that although some inputs were repeated in the `fancy_products` tables, none of the
repetitions led to additional calls to the eager producer or to entries in the cache.

## DEMO II: Summing Up, Speculatively

In this demo, let me demonstrate how to write a speculative value producer, that is, a producer that does
more work when called than is strictly necessary in order to avoid getting called more often. Such a
behavior might shave off some computation time when the act of computing a single value is associated with a
high overhead cost that remains more or less constant no matter how many values are produced, and we have
either a way to somehow predict what other values might get requested in the future when given a set of
inputs, or we can somehow make sure a given subdomain of values can be exhaustively cached. For example,
there might be a configuration file that must be laoded and parsed in order to obtain a single configuration
setting in the file; in such a case, it might be advantageous to cache all the settings from the file
whenever any setting is requested so that future setting requests can be answered by a table lookup.

### Step 1: Write a Speculative Eager Value Producer

The eager value producer of the first example was an immutable function that returns a single value. In
order to do speculative caching, we'll need a volatile function that updates the cache directly. In its most
basic form, such a cache updating function might look like this:

```sql
create function MYSCHEMA.insert_sums_single_row( ¶a integer, ¶b integer )
  returns void volatile called on null input language plpgsql as $$ begin
    raise notice 'MYSCHEMA.insert_sums( %, % )', ¶a, ¶b;
    insert into LAZY.cache ( bucket, key, value ) values
      ( 'yeah! sums!', to_jsonb( array[ ¶a, ¶b ] ), ¶a + ¶b );
      -- ^^^^ bucket   ^^^^ key                     ^^^^^^^ value
    end; $$;
```

This is only the basic shape however and will only insert a single row which, as such, is not very
speculative. Here is an improved version that guesses a few sums that might pop up in the future—namely,
given `[ a, b ]`, it will compute `a + b - 1`, `a + b`, and `a + b + 1`, minus those sums that already have
an cache entry:

```sql
create function MYSCHEMA.insert_sums( ¶a integer, ¶b integer )
  returns void volatile called on null input language plpgsql as $$ begin
    raise notice 'MYSCHEMA.insert_sums( %, % )', ¶a, ¶b;
    insert into LAZY.cache ( bucket, key, value ) select
        'yeah! sums!'                                 as bucket,
        r2.key                                        as key,
        ¶a + r1.bb                                    as value
      from generate_series( ¶b - 1, ¶b + 1 )        as r1 ( bb  ),
      lateral to_jsonb( array[ ¶a, r1.bb ] )        as r2 ( key ),
      where not exists ( select 1 from LAZY.cache as r4
        where ( bucket = 'yeah! sums!' ) and ( r4.key = r2.key ) );
    end; $$;
```

### Step 2: Create a Lazy Producer

Given `insert_sums()`, we can now create its lazy version, `get_sum()`:

```sql
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_sum',
  parameter_names => '{¶a,¶b}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',
  bucket          => 'yeah! sums!',
  perform_update  => 'MYSCHEMA.insert_sums' );
```

### Step 3: Use the Lazy Value Producer

Just as in the first demo, let's use a table to store results. This time round, we generate the data:

```sql
create table MYSCHEMA.fancy_sums (
  a         integer,
  b         integer,
  result    integer );

insert into MYSCHEMA.fancy_sums ( a, b )
  select 7, b from generate_series( 1, 10 ) as x ( b );
update MYSCHEMA.fancy_sums set result = MYSCHEMA.get_sum( a, b );
select * from LAZY.cache order by bucket, key;
```

And this is the output; notice that while the cache has gained 11 entries, only 5 calls to the eager
producer was necessary:

```
psql:lazy.demo-2.sql:72: NOTICE:  MYSCHEMA.insert_sums( 7, 1 )
psql:lazy.demo-2.sql:72: NOTICE:  MYSCHEMA.insert_sums( 7, 3 )
psql:lazy.demo-2.sql:72: NOTICE:  MYSCHEMA.insert_sums( 7, 5 )
psql:lazy.demo-2.sql:72: NOTICE:  MYSCHEMA.insert_sums( 7, 7 )
psql:lazy.demo-2.sql:72: NOTICE:  MYSCHEMA.insert_sums( 7, 9 )
╔═════════════╤═════════╤═══════╗
║   bucket    │   key   │ value ║
╠═════════════╪═════════╪═══════╣
║ yeah! sums! │ [7, 0]  │ 7     ║
║ yeah! sums! │ [7, 1]  │ 8     ║
║ yeah! sums! │ [7, 2]  │ 9     ║
║ yeah! sums! │ [7, 3]  │ 10    ║
║ yeah! sums! │ [7, 4]  │ 11    ║
║ yeah! sums! │ [7, 5]  │ 12    ║
║ yeah! sums! │ [7, 6]  │ 13    ║
║ yeah! sums! │ [7, 7]  │ 14    ║
║ yeah! sums! │ [7, 8]  │ 15    ║
║ yeah! sums! │ [7, 9]  │ 16    ║
║ yeah! sums! │ [7, 10] │ 17    ║
╚═════════════╧═════════╧═══════╝
```

Note that in case an eager inserting value producer should not insert a value for a given requested key, the
lazy value producer will then auto-generate a row with `null` value. This behavior may become configurable
in a future version.

## Bonus: Setting up Custom Cache Views

Since it may sometimes be useful to have a view on the data already cached by a given lazy producer, here's
how to do it. It is basically straightforward: the key is by default formed by building a `jsonb` array of
the arguments (although one can define one's own keying method); likewise, values are stored as `jsonb`
values so these have to be converted back to the intended data type. Which is not difficult to do, except
that `jsonb` has its own `null` value which, unlike SQL `null`, cannot be cast; this is what
`LAZY.nullify()` is for:

```sql
create view MYSCHEMA.products as ( select
      ( LAZY.nullify( key->0 ) )::float as n,
      ( LAZY.nullify( key->1 ) )::float as factor,
      ( value                  )::float as product
    from LAZY.cache
    where bucket = 'MYSCHEMA.get_product'
    order by n desc, factor desc );
```

```
╔═════╤════════╤═════════╗
║  n  │ factor │ product ║
╠═════╪════════╪═════════╣
║   ∎ │      ∎ │       0 ║
║   ∎ │    100 │       0 ║
║ 123 │    456 │   56088 ║
║  60 │      3 │     180 ║
║  13 │     13 │       ∎ ║
║ 6.3 │     12 │    75.6 ║
║   6 │     12 │      72 ║
║   5 │     12 │      60 ║
║   4 │     12 │      48 ║
║   1 │      ∎ │       0 ║
╚═════╧════════╧═════════╝
```

# Updates

* **v1.0.0**—Values are now stored as `text` rather than as `jsonb`, the reason being that
  * all datatypes have a `text` serialization (this is mandatory as DB dumps could otherwise not be
    produced), but not all datatypes can be expressed in JSON in a straightforward way, meaning customized
    conversion functions `mytype_from_jsonb()` / `mytype_to_jsonb()` are needed where otherwise simple type
    casts `myvalue::text` / `textvalue::mytype` would be sufficient.
  * While quering `jsonb` values is much more flexible, one will typically search over keys, not results;
    where quering against result values is needed, one can still cast the `text` values (e.g. in a
    (materialized) view).

# To Do

* [X] Documentation
* [X] Tests
* [X] consider to optionally use a text-based cache


