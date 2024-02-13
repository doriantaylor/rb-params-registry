# frozen_string_literal: true

require_relative 'types'

# This class represents a parsed instance of a set of parameters. It
# is intended to be used like a {::Hash}, and, among other things,
# manages the serialization of the parameters back into a normalized
# query string.
#
class Params::Registry::Instance

  private

  # i wish it was smart and would just resolve relative class names
  Types = Params::Registry::Types

  # This is the epitome of an internal method. It has weird
  # parameters, modifies state, and returns a value that is useless
  # for anything but subsequent internal processing.
  def process_one template, values, complement: false, force: false
    del = Set[]

    # run the preprocessor
    if template.preproc? and template.consumes.all? { |k| @content.key? k }
      others = @content.values_at(*template.consumes)

      # XXX maybe we should
      values = template.preproc values, others
      del += template.consumes
    end

    # if this actually goes here then there's a bug in the perl one
    return del if values.empty? and not force

    # now we use the template to process it (note this raises)
    tmp = template.process(*values)
    @content[template.id] = tmp if !tmp.nil? or template.empty?

    # now we test for conflicts
    tc = template.conflicts - template.consumes - del.to_a
    unless tc.empty?
      conflicts = @content.keys & tc
      raise Params::Registry::Error::Conflict.new(
        "Parameter #{template.id} conflicts with #{conflicts.join(', ')}"
      ) unless conflicts.empty?
    end

    # now we handle the complement
    @content[template.id] = template.complement(@content[template.id]) if
      complement and template.complement?

    del # the keys slated for deletion
  end

  public

  attr_reader :registry

  # Make a new instance.
  #
  # @param registry [Params::Registry] the registry
  # @param struct [Hash{Symbol => Array<String>}] something that
  #  resembles the output of `URI.decode_www_form`.
  #
  def initialize registry, struct, defaults: false, force: false
    if registry.is_a? Params::Registry::Group
      @group    = registry.id
      @registry = registry = registry.registry
    else
      @group    = nil
      @registry = registry
    end

    @content  = {}
    @extra    = {}

    warn "wtf lol #{@registry[@group].inspect}"

    # canonicalize the keys of the struct
    struct = Types::Input[struct].reduce({}) do |hash, pair|
      key, value = pair
      if t = @registry[@group][key]
        warn "yep #{key.inspect}"
        hash[t.id] = value
      else
        warn "nope #{key.inspect}"
        @extra[key] = value
      end

      hash
    end

    errors = {} # collect errors so we only raise once at the end
    del = Set[] # mark for deletion

    # grab the complements now
    complements = @content[@registry.complement.id] =
      @registry.complement.process(*struct.fetch(@registry.complement.id, []))

    # warn registry.templates.ranked.inspect

    # warn complements.class

    # now we get the ranked templates and pass them through
    @registry[@group].ranked.each do |templates|
      # give me the intersection of templates
      templates.values.each do |t|

        # warn t.id

        # obtain the raw values or an empty array instead
        raw = struct.fetch t.id, []

        c = complements.include? t.id

        begin
          del += process_one t, raw, force: force, complement: c
        rescue Params::Registry::Error => e
          errors[t.id] = e
        end

      end
    end

    # raise any errors if we need to
    raise Params::Registry::Error::Processing.new(
      'One or more parameters failed to process', errors: errors) unless
      errors.empty?

    # delete the unwanted parameters
    del.each { |d| @content.delete d }
  end

  # Retrieve the processed value for a parameter.
  #
  # @param param [Object, #to_sym] the parameter identifier, or
  #  slug, or alias.
  #
  # @return [Object, Array, nil] the value, if present.
  #
  def [] param
    param = @registry.templates.canonical(param) or return @extra[param]
    @content[param]
  end

  # Assign a new value to a key. The new value will be tested
  # against the `composite` type if one is present, then an
  # {::Array} of the ordinary atomic type if the cardinality is
  # greater than 1, then finally the atomic type.
  #
  # @param param [Object, #to_sym] the parameter identifier, or
  #  slug, or alias.
  # @param value [Object, Array] the value, which is subject to type
  #  assertion/coercion.
  #
  # @return [Object, Array] the value(s) associated with the
  #  parameter.
  #
  def []= param, value
    unless template = registry.templates[param]
      value = value.respond_to?(:to_a) ? value.to_a : value
      return @extras[param] = value
    end

    # XXX do something less dumb about this
    c = (@content[registry.complement.id] || Set[]).include? template.id

    # this modifies @content and may raise
    del = process_one template, value, force: true, complement: c

    del.each { |d| @content.delete d }

    # return
    @content[template.id]
  end

  # Taxidermy this object as an ordinary hash.
  #
  # @param slugs [true, false] whether to use slugs versus canonical keys.
  # @param extra [false, true] whether to include the "extra" parameters.
  #
  # @return [Hash] basically the same thing, minus its metadata.
  #
  def to_h slugs: true, extra: false
    # we're gonna do damage, lol
    out = @content.dup

    # this should work?
    out.transform_keys! do |k|
      registry[@group][k].slug || k.to_s.to_sym
    end if slugs

    # XXX maybe enforce the ordering better??
    out.merge! @extra if extra

    out
  end

  # Retrieve an {Params::Registry::Instance} that isolates the
  # intersection of one or more groups
  #
  # @param group [Object] the group identifier.
  # @param extra [false, true] whether to include any "extra" unparsed
  #  parameters.
  #
  # @return [Params::Registry::Instance] an instance containing just
  #  the group(s) identified.
  #
  def group *group, extra: false
  end

  # Serialize the instance back to a {::URI} query string.
  #
  # @return [String] the instance serialized as a URI query string.
  #
  def to_s
    ts = registry.templates
    sequence = ts.keys & @content.keys
    complements = Set[]
    sequence.map do |k|
      template = ts[k]
      deps = @content.values_at(*(template.depends - template.consumes))
      v, c = template.unprocess @content[k], *deps, with_complement_flag: true
      complements << k if c

      # warn @content[k], v.inspect

      next if v.empty?

      v.map { |v| "#{template.slug || k}=#{v}" }.join ?&
    end.compact.join ?&
  end
end
