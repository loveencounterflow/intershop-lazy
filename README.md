# InterShop Lazy

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

  - [Purpose](#purpose)
  - [Value Producers](#value-producers)
  - [Result Type](#result-type)
- [API](#api)
  - [Methods Concerning Return Values](#methods-concerning-return-values)
  - [Methods to Create Lazy Value Producers](#methods-to-create-lazy-value-producers)
  - [Private Methods](#private-methods)
- [Complete Demo](#complete-demo)
  - [Step 1: Write a Value Producer](#step-1-write-a-value-producer)
- [To Do](#to-do)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Purpose

InterShop Lazy provides a way to (almost) transparently store results of costly computations in a table for
later retrieval.

* value producer



## Value Producers

Value producers are assumed to be 'immutable' functions in the PostGres sense, i.e. 'pure functions' in the
functional sense.

Value producers *must* return value of type `LAZY.jsonb_result` which is a composite type that value
producers can communicate the 'happy' or 'sad' outcomes of computations. Since the field for the result
proper (named `ok` similar to Rust's `Result` type) has type `jsonb`, the set of all happy results is the
set of values that can be represented by PostGreSQL's `jsonb` data type.

Value producers must not raise exceptions during normal operation; when they do, no attempt is made
by InterShop Lazy to handle them. However, value producers *can* return 'sad' results.

* `called on null input`

## Result Type

`LAZY.jsonb_result` is a composite type with 3 fields:

* `ok` (`jsonb`),
* `error` (`text`).

A result is said the be 'happy' when its field `error` is `null`; conversely, it is said to be 'sad' when
its field `error` holds an error message. In either case, the returned value will be stored in the
`LAZY.facets` table.


# API

## Methods Concerning Return Values

* **`LAZY.is_happy( LAZY.jsonb_result ) returns boolean`**— returns whether a given result is happy.
* **`LAZY.is_sad( LAZY.jsonb_result ) returns boolean`**—returns whether a given result is sad.
* **`LAZY.happy( ok jsonb ) returns LAZY.jsonb_result`**—given a `jsonb` value, returns the same wrapped
  into a `LAZY.jsonb_result` composite type. This is the method that most value producers will use most of
  the time to return happy results.
* **`LAZY.sad( error text ) returns LAZY.jsonb_result`**—given an error message, return a
  `LAZY.jsonb_result` where `ok` is set to `null` and `error` is set to the message given.

## Methods to Create Lazy Value Producers

```sql
LAZY.create_lazy_producer(
  function_name     text,               -- name of function to be created
  parameter_names   text[],
  parameter_types   text[],
  return_type       text,               -- applied to cached value or value returned by caster
  bucket            text default null,  -- optional, defaults to `function_name`
  get_key           text default null,  -- optional, default is JSON list / object of values
  get_update        text default null,  -- optional, this x-or `perform_update` must be given
  perform_update    text default null,  -- optional, this x-or `get_update` must be given
  caster            text default null ) -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  returns void volatile called on null input language plpgsql as $$
```

## Private Methods

* **`LAZY._normalize( LAZY.jsonb_result ) returns LAZY.jsonb_result`**—Given a `LAZY.jsonb_result` value or
  `null`, return a LAZY.jsonb_result value with all three fields set to null if either the value is `null`,
  or its `ok` field is `null` or JSONB `''null''`; otherwise, return the value itself. This function is used
  internally; its effect is that the potentially distinct results that all indicate a `null` result are
  uniformly represented as a `(null,null)` pair.

* **`create function LAZY._normalize( LAZY.facets ) returns LAZY.facets`**—Ensures that a given value to be
  inserted to `LAZY.facets` is not SQL `null` (this is expressed by `(null,null)` instead) and that the `ok`
  field of the result is SQL `null` and not any other value in case the `error` field isn't `null`.

# Complete Demo

The below code can be seen in action by running `psql -f lazy.demo-1.sql`.

## Step 1: Write a Value Producer

The first thing to do when one wants to use lazy evaluation with InterShop Lazy is to provide a function
that accepts arguments as required and that returns a `LAZY.jsonb_result` value. `LAZY.jsonb_result`
provides one field for happy results and one for sad results that will cause an exception. Value Producers
should be immutable functions that never throw under normal conditions; instead, use `LAZY.sad( 'message' )`
to communicate that a given combination of arguments should cause an exception. This exception will be
stored just like a regular result would and will lead to same exception whenever the same combination of
values is requested later.

Of course, using lazy evaluation makes only sense when one is dealing with costly computations, but for the
sake of example, let's just produce arithmetic products here (but with a quirk to show off features). A
value producer for multiplication could look as simple as this:

```sql
create function MYSCHEMA.compute_product( ¶n integer, ¶factor integer )
  returns LAZY.jsonb_result immutable called on null input language plpgsql as $$ declare
  begin return LAZY.happy( ¶n * ¶factor ); end; $$;
```

In the present example, however, we will use a slightly more involved one: we want to raise errors whenever
one of the multiplicands is `null`, and another one if the first one (called `¶n` here) is `13` and the
second one (`¶factor`) is even. If `¶n` is `13` and `¶factor` is odd, we want the outcome to be `null`; this
covers all of the behavoral variants possible:

```sql
create function MYSCHEMA.compute_product( ¶n integer, ¶factor integer )
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
```


```sql
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product',            -- name of function to be created
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',                         -- applied to cached value or value returned by caster
  get_key         => null,                              -- optional, default is JSON list / object of values
  get_update      => 'MYSCHEMA.compute_product',        -- optional, this x-or `perform_update` must be given
  perform_update  => null,                              -- optional, this x-or `get_update` must be given
  caster          => null                               -- optional, to transform JSONB value in to `return_type` (after `caster()` called where present)
  );
```


# To Do

* [ ] Documentation
* [ ] Tets


