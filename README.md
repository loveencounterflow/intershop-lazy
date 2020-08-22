# InterShop Lazy

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

  - [Purpose](#purpose)
  - [Value Producers](#value-producers)
- [API](#api)
  - [Methods to Create Lazy Value Producers](#methods-to-create-lazy-value-producers)
  - [Private Methods](#private-methods)
- [Complete Demo](#complete-demo)
  - [Step 1: Write a Value Producer](#step-1-write-a-value-producer)
  - [Step 2: Create a Lazy Producer](#step-2-create-a-lazy-producer)
  - [Use the Lazy Value Producer](#use-the-lazy-value-producer)
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

## Private Methods

* **`LAZY._normalize( jsonb ) returns jsonb`**—Given a `jsonb` value or
  `null`, return a jsonb value with all three fields set to null if either the value is `null`,
  or its `ok` field is `null` or jsonb `''null''`; otherwise, return the value itself. This function is used
  internally; its effect is that the potentially distinct results that all indicate a `null` result are
  uniformly represented as a `(null,null)` pair.


# Complete Demo

The below code can be seen in action by running `psql -f lazy.demo-1.sql`.

## Step 1: Write a Value Producer

The first thing to do when one wants to use lazy evaluation with InterShop Lazy is to provide a function
that accepts arguments as required and that returns a `jsonb` value. The convenience functions
`LAZY.happy()` and `LAZY.sad()` make it easy to produce such results; in addition, SQL `null` may be
returned as-is to signal cases where consumers should receive a `null` for a given computation.

Of course, using lazy evaluation makes only sense when one is dealing with costly computations, but for the
sake of example, let's just produce arithmetic products here (but with a quirk to show off features). A
value producer for multiplication could look as simple as this:

```sql
create function MYSCHEMA.compute_product( ¶n integer, ¶factor integer )
  returns integer immutable called on null input language sql as $$
  select ¶n * ¶factor; $$;
```


## Step 2: Create a Lazy Producer

All access to the value producer should go through the function that is created by
`LAZY.create_lazy_producer()`; this is the only one that data consumers will have to use (although they can
of course inspect `LAZY.cache()` where computed values are kept). `create_lazy_producer()` takes quite
a few arguments, but half of them are optional. The arguments are:

```sql
select LAZY.create_lazy_producer(
  function_name   => 'MYSCHEMA.get_product',
  parameter_names => '{¶n,¶factor}',
  parameter_types => '{integer,integer}',
  return_type     => 'integer',
  get_update      => 'MYSCHEMA.compute_product' );
```

The first argument here is the name of the function that computes values that have not been inserted into
the caching table `LAZY.cache` already; the next 3 arguments basically repeat the declarative part to that
function and will possibly be auto-generated in a future version of InterShop Lazy.

There's just one more required argument, either `get_update` or `perform_update`; exactly one of these two
must be set to the name of a function that either

* in the case of `get_update()`, will return exactly one result for each set of inputs, or
* in the case of `perform_update()`, may insert as many rows into `LAZY.cache` as seen fit when called. In
  case `perform_update()` happened to not produce a result line that matches the input arguments, a line
  with result `null` will be auto-generated.

## Use the Lazy Value Producer

We're now ready to put our caching, lazy multiplicator device to use:

```sql
select * from LAZY.cache order by bucket, key;
select * from MYSCHEMA.get_product( 4, 12 );
select * from MYSCHEMA.get_product( 5, 12 );
select * from MYSCHEMA.get_product( 6, 12 );
select * from MYSCHEMA.get_product( 60, 3 );
select * from MYSCHEMA.get_product( 13, 13 );
select * from LAZY.cache order by bucket, key;
```

This will produce the following output:

```
╔════════╤═════╤═══════╗
║ bucket │ key │ value ║
╠════════╪═════╪═══════╣
╚════════╧═════╧═══════╝

╔═════════════╗
║ get_product ║
╠═════════════╣
║          48 ║
╚═════════════╝

╔═════════════╗
║ get_product ║
╠═════════════╣
║          60 ║
╚═════════════╝

╔═════════════╗
║ get_product ║
╠═════════════╣
║          72 ║
╚═════════════╝

╔═════════════╗
║ get_product ║
╠═════════════╣
║         180 ║
╚═════════════╝

╔═════════════╗
║ get_product ║
╠═════════════╣
║           ∎ ║
╚═════════════╝

╔══════════════════════╤══════════╤════════╗
║        bucket        │   key    │ value  ║
╠══════════════════════╪══════════╪════════╣
║ MYSCHEMA.get_product │ [4, 12]  │ (48,)  ║
║ MYSCHEMA.get_product │ [5, 12]  │ (60,)  ║
║ MYSCHEMA.get_product │ [6, 12]  │ (72,)  ║
║ MYSCHEMA.get_product │ [13, 13] │ (,)    ║
║ MYSCHEMA.get_product │ [60, 3]  │ (180,) ║
╚══════════════════════╧══════════╧════════╝
```

As can be seen, not only does the multiplicator excel in integer arithmetics, it also keeps track of past
results. If we were to repeat any of the above calls, no additional calls to `get_product()` would be
performed, nor would any lines be added to `LAZY.cache`. That can save tons of cycles and waiting time!

Keep in mind that *almost* the same effect can be achieved in PostGreSQL by declaring a function `immutable`
since PG caches results to immutable functions internally. However, while those caches will not survive DB
sessions, data stored by InterShop Lazy will.

Also observe that `get_product()` will refuse to compute multiples of `13`; this is where the `null` result
for `get_product( 13, 13 )` came from. Had we requested the result of `13 * 12` instead, an exception would
have been raised:

```sql
select * from MYSCHEMA.get_product( 13, 12 );
```


```
psql:lazy.demo-1.sql:83: ERROR:  LZE00 will not produce even multiples of 13
CONTEXT:  PL/pgSQL function lazy.unwrap(lazy.jsonb_result) line 8 at RAISE
PL/pgSQL function myschema.get_product(integer,integer) line 16 at RETURN
```


# To Do

* [ ] Documentation
* [ ] Tets


