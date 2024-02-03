# frozen_string_literal: true

require_relative 'types'
require_relative 'error'

# This class manages an individual parameter template.
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
  # @param unwind [Proc] A function that takes the composite type
  #  and turns it into an {::Array} of atomic values
  # @param reverse [false, true] For {::Range} composite types, a flag
  #  that indicates whether the values should be interpreted and/or
  #  serialized in reverse order. Also governs the serialization of
  #  {::Set} composites.
  #
  def initialize registry, id, slug: nil, type: Types::NormalizedString,
      composite: nil, format: nil, aliases: nil, depends: nil, conflicts: nil,
      consumes: nil, preproc: nil, min: 0, max: nil, shift: false,
      empty: false, default: nil, universe: nil, complement: nil,
      unwind: nil, reverse: false

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
    @unifunc    = Types::Proc[universe]   if universe
    @complement = Types::Proc[complement] if complement
    @unwind     = Types::Proc[unwind]     if unwind
    @reverse    = Types::Bool[reverse]

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
  # @!attribute [r] unwind
  # A function that will take a composite object
  #  and turn it into an array of strings for serialization.
  # @return [Proc, nil]

  attr_reader :registry, :id, :slug, :type, :composite, :aliases,
    :preproc, :min, :max, :default, :unwind

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
    refresh! unless @universe
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
      @unifunc.nil? && @complement.nil? && @unwind.nil? && !@reverse
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
  # @param values [Array] the values given for the parameter.
  #
  # @return [Object, Array] the processed value(s).
  #
  def process *values
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
      tmp, comp = instance_exec value, *rest, &@unwind
      value = tmp
    rescue Exception, e
      raise Params::Registry::Error::Empirical.new(
        "Cannot unprocess value #{value} for parameter #{id}: #{e.message}",
        context: self, value: value)
    end if @unwind

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

    nil
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
