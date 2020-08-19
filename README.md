# InterShop Lazy

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

  - [Purpose](#purpose)
  - [Value Producers](#value-producers)
  - [Result Type](#result-type)
- [API](#api)
  - [Methods Concerning Return Values](#methods-concerning-return-values)
  - [Methods to Create Value Producers](#methods-to-create-value-producers)
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

## Result Type

`LAZY.jsonb_result` is a composite type with 3 fields:

* `ok` (`jsonb`),
* `sqlstate` (`text`) and
* `sqlerrm` (`text`).

A result is said the be 'happy' when both of the fields `sqlstate` (containing an error code) or `sqlerrm`
(containing an error message) are `null`; conversely, it is said to be 'sad' when at least one of these
fields is not `null`. In either case, the returned value will be stored in the `LAZY.facets` table.


# API

## Methods Concerning Return Values

* **`LAZY.is_happy( LAZY.jsonb_result ) returns boolean`**— returns whether a given result is happy.
* **`LAZY.is_sad( LAZY.jsonb_result ) returns boolean`**—returns whether a given result is sad.
* **`LAZY.happy( ok jsonb ) returns LAZY.jsonb_result`**—given a `jsonb` value, returns the same wrapped
  into a `LAZY.jsonb_result` composite type. This is the method that most value producers will use most of
  the time to return happy results.
* **`LAZY.sad( sqlerrm text ) returns LAZY.jsonb_result`**—given an error message, return a
  `LAZY.jsonb_result` where `ok` is set to `null` and `sqlstate` is set to `LZ000`. Use this method in case
  your value producer does need to return sad values but has no incentive to distinguish between different
  error conditions.
* **`LAZY.sad( sqlstate text, sqlerrm text ) returns LAZY.jsonb_result`**—Same as before, but with the
  possibility to specify an error code.

## Methods to Create Value Producers

```sql
LAZY.create_lazy_function(
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


# To Do

* [ ] Documentation
* [ ] Tets


