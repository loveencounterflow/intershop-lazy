# InterShop Lazy

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

  - [Purpose](#purpose)
  - [Value Producers](#value-producers)
  - [Result Type](#result-type)
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


# To Do

* [ ] Documentation
* [ ] Tets


