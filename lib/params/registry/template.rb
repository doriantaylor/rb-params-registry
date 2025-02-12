# frozen_string_literal: true

require_relative 'types'
require_relative 'error'

# This class manages an individual parameter template. It encapsulates
# all the information and operations needed to validate and coerce
# individual parameter values, as well as for serializing them back
# into a string, and for doing so with bit-for-bit consistency.
#
# A parameter template can have a human-readable {::Symbol} as a
# `slug`, which is distinct from its canonical identifier (`id`),
# which can be any object, although that must be unique for the entire
# registry (while a slug only needs to be unique within its enclosing
# group). It can also have any number of `aliases`.
#
# A template can manage a simple type like a string or number, or a
# composite type like an array, tuple (implemented as a fixed-length
# array), set, or range containing appropriate simple types. The
# current (provisional) way to specify the types for the template are
# the `type` and `composite` initialization parameters, where if the
# latter is present, the former will be treated as its member type.
#
# > If certain forays into open-source diplomacy go well, these can be
# > consolidated into a single type declaration.
#
# A parameter may depend on (`depends`) or conflict (`conflicts`) with
# other parameters, or even consume (`consumes`) them as input. The
# cardinality of a parameter is controlled by `min` and `max`, which
# default to zero and unbounded, respectively. To require a parameter,
# set `min` to an integer greater than zero, and to enforce a single
# scalar value, set `max` to 1. (Setting `min` greater than `max` will
# raise an error.) To control whether a value of `nil` or the empty
# string is dropped, kept (as the empty string) or kept as `nil`, set
# the `empty` parameter.
#
# When `max` is greater than 1, the template automatically coerces any
# simple value into an array containing that value. (And when `max` is
# equal to 1, an array will be replaced with a single value.) Passing
# an array into #process with fewer than `min` values (or a single
# value when `min` is greater than 1) will produce an error. Whether
# the first N values (up to `max`) or the _last_ N values are taken
# from the input, is controlled by the `shift` parameter.
#
# Composite values begin life as arrays of simple values. During
# processing, the individual values are coerced from what are assumed
# to be strings, and then the arrays themselves are coerced into the
# composite types. Serialization is the same thing in reverse, using a
# function passed into `unwind` (which otherwise defaults to `to_a`)
# to turn the composite type back into an array, before the individual
# values being turned into strings by way of the value passed into
# `format`, which can either be a standard format string or a
# {::Proc}. The `unwind` function is also expected to sort the
# array. There is also a `reverse` flag for when it makes sense to
#
# The transformation process, from array of strings to composite
# object and back again, has a few more points of intervention. There
# is an optional `preproc` function, which is run after the individual
# values are coerced and before the composite coercion is applied, and
# a `contextualize` function, which is run after `unwind` but before
# `format`. Both of these functions make it possible to use
# information from the parameter's dependencies to manipulate its
# values based on its context within a live {Params::Registry::Instance}.
#
# Certain composite types, such as sets and ranges, have a coherent
# concept of a `universe`, which is implemented here as a function
# that generates a compatible object. This is useful for when the
# serialized representation of a parameter can be large. For instance,
# if a set's universe has 100 elements and we want to represent the
# subset with all the elements except for element 42, rather than
# serializing a 99-element query string, we complement the set and
# make a note to that effect (to be picked up by the
# {Params::Registry::Instance} serialization process and put in its
# `complement` parameter). The function passed into `complement` will
# be run as an instance method, which has access to `universe`.
#
# > Indeed, all supplied {::Proc}s are run via `instance_exec`.
#
# The `preproc` and `contextualize` functions are of the form
# `-> value, hash { expr }` and return an array. The `unwind` and
# `complement` functions both take the composite value as an argument
# and return an object of the same type. The `universe` function takes
# no arguments and returns a composite object.
#
class Params::Registry::Template

  private

  # this is dumb
  Types = Params::Registry::Types

  # Post-initialization hook for subclasses, because the constructor
  # is so hairy.
  #
  # @return [void]
  #
  def post_init; end

  public

  # Initialize the template object.
  #
  # @param registry [Params::Registry] A backreference to the
  #  parameter registry
  # @param id [Object] The canonical, unique identifier for the
  #  parameter
  # @param slug [#to_sym] A "friendly" symbol that will end up in
  #  the serialization
  # @param aliases [Array<#to_sym>] Alternative nicknames for the
  #  parameter
  # @param type [Dry::Types::Type, Symbol, Proc] An "atomic" type
  #  for single values
  # @param composite [Dry::Types::Type, Symbol, Proc] A composite
  #  type into which multiple values are loaded
  # @param format [String, Proc, nil] A format string or function
  # @param depends [Array] Parameters that this one depends on
  # @param conflicts [Array] Parameters that conflict with this one
  # @param consumes [Array] Parameters that can be given in lieu of
  #  this one, that will be composed into this one. Parameters this
  #  one `consumes` implies `depends` _and_ `conflicts`.
  # @param preproc [Proc, nil] A preprocessing function that is fed
  #  parameters from `consumes` and `depends` to generate this
  #  parameter
  # @param min [Integer, nil] Minimum cardinality
  # @param max [Integer, nil] Maximum cardinality
  # @param shift [false, true] When given more than `max` values, do
  #  we take the ones we want from the back or from the front
  # @param empty [false, true, nil] whether to treat an empty value
  #  as nil, the empty string, or discard it
  # @param default [Object, nil] A default value
  # @param universe [Proc] For {::Set} or {::Range} composite types and
  #  derivatives, a function that returns the universal set or range
  # @param complement [Proc] For {::Set} or {::Range} composite types, a
  #  function that will return the complement of the set or range
  # @param unwind [Proc] A function that takes a composite type
  #  and turns it into an {::Array} of atomic values
  # @param contextualize [Proc] A function that takes an unwound
  #  composite value and modifies it based on the other parameters it
  #  depends on
  # @param reverse [false, true] For {::Range} composite types, a flag
  #  that indicates whether the values should be interpreted and/or
  #  serialized in reverse order. Also governs the serialization of
  #  {::Set} composites.
  #
  def initialize registry, id, slug: nil, type: Types::NormalizedString,
      composite: nil, format: nil, aliases: nil, depends: nil, conflicts: nil,
      consumes: nil, preproc: nil, min: 0, max: nil, shift: false,
      empty: false, default: nil, universe: nil, complement: nil,
      unwind: nil, contextualize: nil, reverse: false

    @registry   = Types::Registry[registry]
    @id         = Types::NonNil[id]
    @slug       = Types::Symbol[slug] if slug
    @type       = Types[type]
    @composite  = Types[composite] if composite
    @format     = (Types::Proc | Types::String)[format] if format
    @aliases    = Types::Array[aliases]
    @depends    = Types::Array[depends]
    @conflicts  = Types::Array[conflicts]
    @consumes   = Types::Array[consumes]
    @preproc    = Types::Proc[preproc] if preproc
    @min        = Types::NonNegativeInteger[min || 0]
    @max        = Types::PositiveInteger.optional[max]
    @shift      = Types::Bool[shift]
    @empty      = Types::Bool[empty]
    @default    = Types::Nominal::Any[default]
    @unifunc    = Types::Proc[universe]      if universe
    @complement = Types::Proc[complement]    if complement
    @unwfunc    = Types::Proc[unwind]        if unwind
    @confunc    = Types::Proc[contextualize] if contextualize
    @reverse    = Types::Bool[reverse]

    raise ArgumentError, "min (#{@min}) cannot be greater than max (#{@max})" if
      @min and @max and @min > @max

    # post-initialization hook
    post_init
  end

  # @!attribute [r] registry
  #  @return [Params::Registry] a backreference to the registry.
  #
  # @!attribute [r] id
  #  @return [Object] the canonical identifier for the parameter.
  #
  # @!attribute [r] slug
  #  @return [Symbol, nil] the primary nickname for the parameter, if
  #   different from the `id`.
  #
  # @!attribute [r] type
  #  @return [Dry::Types::Type] the type for individual parameter values.
  #
  # @!attribute [r] composite
  #  @return [Dry::Types::Type, nil] the type for composite values.
  #
  # @!attribute [r] aliases
  #  @return [Array<Symbol>] any aliases for this parameter.
  #
  # @!attribute [r] preproc
  #  @return [Proc] a procedure to run over `consume`d parameters.
  #
  # @!attribute [r] min
  #  @return [Integer] minimum cardinality for the parameter's values.
  #
  # @!attribute [r] max
  #  @return [Integer, nil] maximum cardinality for the parameter's values.
  #
  # @!attribute [r] default
  #  @return [Object, nil] a default value for the parameter.
  #
  attr_reader :registry, :id, :slug, :type, :composite, :aliases,
    :preproc, :min, :max, :default

  # @!attribute [r] unwind
  # A function that will take a composite object
  #  and turn it into an array of strings for serialization.
  # @return [Proc, nil]

  def unwind value, *dependencies, try_complementing: false
    return unless composite?
    deps = depends - consumes
    raise ArgumentError,
      "Unwinding #{id} requires dependencies #{deps.join ', '}" unless
      dependencies.length >= deps.length

    func = @unwfunc || proc { |v| v.to_a }
    out  = instance_exec value, *dependencies.take(deps.length), &func

    if try_complementing
      diff = universe - out
      if diff.size > out.size
      end
    end

    out
  end

  # @!attribute [r] depends
  # Any parameters this one depends on.
  #
  # @return [Array]
  #
  def depends
    out = (@depends | (@preproc ? @consumes : [])).map do |t|
      registry.templates.canonical t
    end

    raise Params::Registry::Error,
      "Malformed dependency declaration on #{t.id}" if out.any?(&:nil?)

    out
  end

  # @!attribute [r] conflicts
  # Any parameters this one conflicts with.
  #
  # @return [Array]
  #
  def conflicts
    out = (@conflicts | (@preproc ? @consumes : [])).map do |t|
      registry.templates.canonical t
    end

    raise Params::Registry::Error,
      "Malformed conflict declaration on #{t.id}" if out.any?(&:nil?)

    out
  end

  # @!attribute [r] composite?
  # Whether this parameter is composite.
  #
  # @return [Boolean]
  #
  def composite? ; !!@composite; end

  # @!attribute [r] preproc?
  # Whether there is a preprocessor function.
  #
  # @return [Boolean]
  #
  def preproc? ; !!@preproc ; end

  # @!attribute [r] consumes
  # Any parameters this one consumes (implies `depends` + `conflicts`).
  #
  # @return [Array]
  #
  def consumes
    out = @consumes.map { |t| registry.templates.canonical t }

    raise Params::Registry::Error,
      "Malformed consumes declaration on #{t.id}" if out.any?(&:nil?)

    out
  end

  # @!attribute [r] universe
  # The universal composite object (e.g. set or range) from which
  #  valid values are drawn.
  # @return [Object, nil]
  def universe
    refresh! if @unifunc and not @universe
    @universe
  end

  # @!attribute [r] shift?
  # Whether to shift values more than `max` cardinality off the front.
  #
  # @return [Boolean]
  #
  def shift? ; !!@shift; end

  # @!attribute [r] empty?
  # Whether to accept empty values.
  #
  # @return [Boolean]
  #
  def empty? ; !!@empty; end

  # @!attribute [r] reverse?
  # Whether to interpret composite values as reversed.
  #
  # @return [Boolean]
  #
  def reverse? ; !!@reverse; end

  # @!attribute [r] complement?
  # Whether this (composite) parameter can be complemented or inverted.
  #
  # @return [Boolean]
  #
  def complement? ; !!@complement; end


  # @!attribute [r] blank?
  # Returns true if the template has no configuration data to speak of.
  # @return [Boolean]
  def blank?
    # XXX PHEWWW
    @slug.nil? && @type == Types::NormalizedString && @composite.nil? &&
      @format.nil? && @aliases.empty? && @depends.empty? &&
      @conflicts.empty? && @consumes.empty? && @preproc.nil? &&
      @min == 0 && @max.nil? && !@shift && !@empty && @default.nil? &&
      @unifunc.nil? && @complement.nil? && @unwfunc.nil? && !@reverse
  end

  # Preprocess a parameter value against itself and/or `consume`d values.
  #
  # @param myself [Array] raw values for the parameter itself.
  # @param others [Array] *processed* values for the consumed parameters.
  #
  # @return [Array] pseudo-raw, preprocessed values for the parameter.
  #
  def preproc myself, others
    begin
      # run preproc in the context of the template
      out = instance_exec myself, others, &@preproc
      out = [out] unless out.is_a? Array
    rescue Dry::Types::CoercionError => e
      # rethrow a better error
      raise Params::Registry::Error.new(
        "Preprocessor failed on #{template.id} with #{}",
        context: self, value: e)
    end

    out
  end

  # Format an individual atomic value.
  #
  # @param scalar [Object] the scalar/atomic value.
  #
  # @return [String] serialized to a string.
  #
  def format scalar
    return scalar.to_s unless @format

    if @format.is_a? Proc
      instance_exec scalar, &@format
    else
      @format.to_s % scalar
    end
  end

  # Return the complement of the composite value for the parameter.
  #
  # @param value [Object] the composite object to complement.
  #
  # @return [Object, nil] the complementary object, if a complement is defined.
  #
  def complement value
    return unless @complement
    begin
      instance_exec value, &@complement
    rescue e
      raise Params::Registry::Error::Empirical.new(
        "Complement function failed: #{e.message}",
        context: self, value: value)
    end if @complement
  end

  # Validate a list of individual parameter values and (if one is present)
  # construct a `composite` value.
  #
  # @param value [Object] the values given for the parameter.
  #
  # @return [Object, Array] the processed value(s).
  #
  def process value
    # we get handed a value, what is it

    # if the template is a composite then try to match it against the
    # composite type (it should be a noop)

    # XXX what we _really_ want is `Types::Set.of` and
    # `Types::Range.of` but who the hell knows how to actually make
    # that happen, so what we're gonna do instead is test if the
    # template is composite, then test the input against the composite
    # type, then run `unwind` on it and test the individual members

    if composite? and composite.try(value).success?
      # okay now we unwind
      value = unwind value
    end

    # otherwise coerce into an array

    out = []

    values.each do |v|
      # skip over nil/empty values unless we can be empty
      if v.nil? or v.to_s.empty?
        next unless empty?
        v = nil
      end

      if v
        begin
          tmp = type[v] # this either crashes or it doesn't
          v = tmp # in which case v is only assigned if successful
        rescue Dry::Types::CoercionError => e
          raise Params::Registry::Error::Syntax.new e.message,
            context: self, value: v
        end
      end

      out << v
    end

    # now we deal with cardinality
    raise Params::Registry::Error::Cardinality.new(
      "Need #{min} values and there are only #{out.length} values") if
      out.length < min

    # warn "hurr #{out.inspect}, #{max}"

    if max
      # return if it's supposed to be a scalar value
      return out.first if max == 1
      # cut the values to length from either the front or back
      out.slice!((shift? ? -max : 0), max) if out.length > max
    end

    composite ? composite[out] : out
  end

  # Applies `unwind` to `value` to get an array, then `format` over
  # each of the elements to get strings. If `scalar` is true, it
  # will also return the flag from `unwind` indicating whether or
  # not the `complement` parameter should be set.
  #
  # This method is called by {Params::Registry::Instance#to_s} and
  # others to produce content which is amenable to serialization. As
  # what happens there, the content of `rest` should be the values
  # of the parameters specified in `depends`.
  #
  # @param value [Object, Array<Object>] The parameter value(s).
  # @param rest  [Array<Object>] The rest of the parameter values.
  # @param with_complement_flag [false, true] Whether to return the
  #  `complement` flag in addition to the unwound values.
  #
  # @return [Array<String>, Array<(Array<String>, false)>,
  #  Array<(Array<String>, true)>, nil] the unwound value(s), plus
  #  optionally the `complement` flag, or otherwise `nil`.
  #
  def unprocess value, *rest, with_complement_flag: false
    # take care of empty properly
    if value.nil?
      if empty?
        return [''] if max == 1
        return [] if max.nil? or max > 1
      end

      # i guess this is nil?
      return
    end

    # complement flag
    comp = false
    begin
      tmp, comp = instance_exec value, *rest, &@unwfunc
      value = tmp
    rescue Exception, e
      raise Params::Registry::Error::Empirical.new(
        "Cannot unprocess value #{value} for parameter #{id}: #{e.message}",
        context: self, value: value)
    end if @unwfunc

    # ensure this thing is an array
    value = [value] unless value.is_a? Array

    # ensure the values are correctly formatted
    value.map! { |v| v.nil? ? '' : self.format(v) }

    # throw in the complement flag
    return value, comp if with_complement_flag

    value
  end

  # Refreshes stateful information like the universal set, if present.
  #
  # @return [void]
  #
  def refresh!
    if @unifunc
      # do we want to call or do we want to instance_exec?
      univ = @unifunc.call

      univ = @composite[univ] if @composite

      @universe = univ
    end

    self
  end

  # Return a suitable representation for debugging.
  #
  # @return [String] the object.
  #
  def inspect
    c = self.class
    i = id.inspect
    t = '%s%s' % [type, composite ? ", #{composite}]" : '']

    "#<#{c} #{i} (#{t})>"
  end

end
