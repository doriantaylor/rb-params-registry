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

  # This method is to process a single parameter _within the context of the
  # entire parameter set_.
  #
  # This is the epitome of an internal method. It has weird
  # parameters, modifies state, and returns a value that is useless
  # for anything but subsequent internal processing.
  def process_one template, values,
      defaults: true, complement: false, force: false

    # unconditionally coerce to array unless it already is one
    values = values.nil? ? [] : values.is_a?(Array) ? values : [values]

    # warn [:process_one, template.slug || template.id, values].inspect

    # set up the set of elements to be deleted
    del = Set[]

    if template.composite? and template.composite.try(values.first).success?
      # do not run the preprocessor
      values = values.first
    elsif template.preproc? and template.consumes.all? { |k| @content.key? k }
      # we prefer the slugs to make it easier on people
      others = @content.slice(*template.consumes).transform_keys do |k|
        t = registry.templates[k]
        t.slug || k
      end

      # run the preproc function
      values = template.preproc values, others

      # add these to the instance parameters to be deleted
      del += template.consumes
    end

    # if this actually goes here then there's a bug in the perl one
    if values.is_a? Array and values.empty? and not force
      # warn "lol wtf #{template.default}"
      @content[template.id] = template.default.dup if
        defaults and not template.default.nil?
      return del
    end

    # now we use the template to process it (note this raises)
    tmp = template.process values
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

  def encode_value value
    # URI::encode_www_form_component sucks
    value = value.to_s.b
    # the only thing we really need to encode is [&=%#] and non-ascii
    # because in a query string all other uri chars are legal
    value.gsub(/[\x0-\x20\x7f-\xff&=%#]/n) { |s| '%%%02X' % s.ord }
  end

  public

  attr_reader :registry, :extra

  # Initialize a parameter instance. Any `params` will be passed to #process.
  #
  # @param registry [Params::Registry, Params::Registry::Group] the registry
  # @param params [String, Hash{Symbol => Array}] something that
  #  resembles either the input or the output of `URI.decode_www_form`.
  #
  def initialize registry, params: nil, defaults: false, force: false
    # deal with registry/group stuff
    if registry.is_a? Params::Registry::Group
      @group    = registry.id
      @registry = registry = registry.registry
    else
      @group    = nil
      @registry = registry
    end

    # set up members
    @content  = {}
    @extra    = {}

    process params, defaults: defaults, force: force if params
  end

  # Process a set of parameters of varying degrees of parsed-ness, up
  # to and including a raw query string.
  #
  # @param params [String, Hash{Symbol => Array}] something that
  #  resembles either the input or the output of `URI.decode_www_form`.
  # @param defaults [true, false] whether to include defaults in the result
  # @param force [false, true] force strict cardinality checking
  #
  # @return [self] for daisy-chaining
  #
  def process params, defaults: true, force: false

    # warn "wtf lol #{@registry[@group].inspect}"

    # warn [:before, params].inspect

    # make sure we get a struct-like object with canonical keys but
    # don't touch the values yet
    params = Types::Input[params].reduce({}) do |hash, pair|
      key, value = pair
      # warn "kv: #{key.inspect} => #{value.inspect}"
      if t = @registry[@group][key]
        # warn "yep #{key.inspect}"
        hash[t.id] = value
      else
        # warn "nope #{key.inspect}"
        @extra[key] = value
      end

      hash
    end

    errors = {} # collect errors so we only raise once at the end
    del = Set[] # mark these keys for deletion

    # grab the complements now
    complements = @content[@registry.complement.id] =
      @registry.complement.process(params.fetch(@registry.complement.id, []))

    # warn registry.templates.ranked.inspect

    # warn [:process, params].inspect

    # now we get the ranked templates and pass them through
    @registry[@group].ranked.each do |templates|
      # give me the intersection of templates
      templates.values.each do |t|

        # warn t.id

        # obtain the raw values or an empty array instead
        raw = params.fetch t.id, []

        c = complements.include? t.id

        begin
          del += process_one t, raw,
            defaults: defaults, force: force, complement: c
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

    # this is a daisy chainer
    self
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
      # XXX THIS IS POTENTIALLY DUMB
      value = value.respond_to?(:to_a) ? value : [value]
      return @extras[param] = value
    end

    @content[template.id] = template.process value
  end

  # Bulk-assign instance content.
  #
  # @param struct [Hash]
  #
  def content= struct
    # just use the member assign we already have
    struct.each { |k, v| self[k] = v }
  end

  # Return a URI with the query set to the string value of this instance.
  #
  # @param uri [URI, #query=] the URI you want to assign
  # @param defaults [false, true] whether to include defaults
  #
  # @return [URI, #query=] the URI with the new query string
  #
  def make_uri uri, defaults: false
    uri = uri.dup
    uri.query = to_s defaults: defaults
    uri
  end

  # Taxidermy this object as an ordinary hash.
  #
  # @param slugs [true, false] whether to use slugs versus canonical keys.
  # @param extra [false, true] whether to include the "extra" parameters.
  #
  # @return [Hash] basically the same thing, minus its metadata.
  #
  def to_h slugs: true, extra: false
    g = registry[@group]

    out = {}

    g.templates.each do |t|
      next unless @content.key? t.id
      key = slugs ? t.slug || t.id.to_s.to_sym : t.id
      out[key] = @content[t.id]
    end

    # XXX maybe enforce the ordering better??
    out.merge! @extra if extra

    out
  end

  # Create a shallow copy of the parameter instance.
  #
  # @return [Params::Registry::Instance] the copy
  #
  def dup
    out = self.class.new @registry[@group]
    out.content = @content.dup
    out
  end

  # Serialize the instance back to a {::URI} query string.
  #
  # @return [String] the instance serialized as a URI query string.
  #
  def to_s defaults: false, extra: false
    ts = registry.templates
    sequence = ts.keys & @content.keys
    complements = Set[]
    sequence.map do |k|
      template = ts[k]
      deps = @content.slice(*(template.depends - template.consumes))
      v, c = template.unprocess @content[k], deps, try_complement: true
      complements << k if c

      # warn @content[k], v.inspect

      next if v.empty?

      v.map do |v|
        "#{template.slug || encode_value(k)}=#{encode_value v}"
      end.join ?&
    end.compact.join ?&
  end

  # Return a string representation of the object suitable for debugging.
  #
  # @return [String] said string representation
  #
  def inspect
    "<#{self.class} content: #{@content.inspect}, extra: #{@extra.inspect}>"
  end
end
