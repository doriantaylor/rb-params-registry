# `Params::Registry`: A registry for named parameters

This module enables an organization to specify a single company-wide
set of named parameters: their syntax, semantics, cardinalities, type
coercions, constraints, conflicts and other interrelationships,
groupings, and so on. The goal is to enforce consistency over
(especially) public-facing parameters and what they mean, promote
re-use, perform input sanitation and other preprocessing chores, and
do consistent, one-to-one, round-trip serialization for things like
URI query strings.

The theoretical underpinning for `Params::Registry` is a phenomenon I
call [the symbol management
problem](https://doriantaylor.com/the-symbol-management-problem),
namely that within a given information system, you have a bunch of
_symbols_, which you have to _manage_, and this is a _problem_.
`Params::Registry` endeavours to take one category of symbols off the
table: named parameters that are exposed to the wild through
mechanisms like URLs and APIs.

## So, query parameters, isn't that like, _super_ anal?

So, I vacillated for _years_ before making [the _first_ version of
this module](https://metacpan.org/dist/Params-Registry) back in 2013.
_Query_ parameters? I mean, who cares? Well, it turns out that if you
want certain outcomes, this is the kind of software you need. _What_
outcomes, you ask?

* Your organization has different parts of its website that use the
  same parameters to mean the same or similar things.
* Your organization has different parts of its website that use
  _different_ parameters to mean the _same_ things.
* Your organization has _more_ than one website, with non-zero overlap
  in their respective functionalities.
* Arbitrary data coming in off the wire (even in something like a
  URL!) is untrustworthy, so it behooves us to check it.
* Some parameters may be required, others optional, or they could have
  complex relationships with each other like dependencies and conflicts.
* Whatever code that consumes the parameters is turning them into some
  kind of object (i.e., not just a primitive datatype like a string or
  integer), potentially combining two or more key-value pairs into
  composites.
* Whatever's consuming the parameters may be able to correct if a
  parameter value is out of bounds (e.g. not in a database), even if
  it is otherwise valid.
* You want to be able to issue redirects in the case of recoverable
  conflicts in the input, and genuinely helpful error messages for the
  non-recoverable ones.

Okay, all that is pretty uncontroversially useful stuff, but
represents something you could probably hack together on an ad-hoc
basis if you really cared. It wouldn't require maintaining an
organization-wide parameter registry. But how about crazy stuff like:

* What if you wanted to round-trip the parameter sets, so that a given
  data structure would _always_ serialize—bit for bit—to the same
  query string, and back again?
* What if you wanted to gracefully handle name changes for the
  parameters, and/or translate their names into different languages?

I shouldn't have to spell out the value of these, but the reason why
you would care about round-tripping the query string is to lower the
footprint out in the wild of URLs that were _different_ lexically but
identified the same resource and/or representational state. The reason
why you would care about parameter naming history is to improve user
experience—directly and via search engines—by catching otherwise
broken links and correcting them (e.g. through a `301` redirect), for
the same purpose. The reason why you would want to localize parameter
names _should_ be obvious, it just shares its mechanism with the
naming history.

In essence, this module takes a category of symbol that couldn't
viably be managed in an organization of even _modest_ size, and makes
it manageable for an organization of _any_ size.

# Contributing

Bug reports and pull requests are welcome at
[the GitHub repository](https://github.com/doriantaylor/rb-params-registry).

# Copyright & License

©2023 [Dorian Taylor](https://doriantaylor.com/)

This software is provided under
the [Apache License, 2.0](https://www.apache.org/licenses/LICENSE-2.0).
