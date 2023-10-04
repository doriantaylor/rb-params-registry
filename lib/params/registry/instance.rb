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

  public

  attr_reader :registry

  # Make a new instance.
  #
  # @param registry [Params::Registry] the registry
  # @param struct [Hash{Symbol => Array<String>}] something that
  #  resembles the output of `URI.decode_www_form`.
  #
  def initialize registry, struct, defaults: false, force: false
    struct    = Types::Input[struct]
    @registry = registry
    @content  = {}
    @extra    = {}

    # let's get a mapping of the input we have to canonical identifiers
    mapping = struct.keys.reduce({}) do |hash, key|
      if t = registry.templates[key]
        hash[t.id] = key
      else
        # may as well designate the extras
        extra[key] = struct[key]
      end

      hash
    end

    # warn mapping.inspect

    errors = {} # collect errors so we only raise once at the end
    del = Set[] # mark for deletion

    # warn registry.templates.ranked.inspect

    # now we get the ranked templates and pass them through
    registry.templates.ranked.each do |templates|
      # give me the intersection of templates
      templates.values.each do |t|
        # warn t.id

        # obtain the raw values
        raw = mapping.key?(t.id) ? struct[mapping[t.id]] : []

        # warn @content.inspect

        # run the preprocessor
        if t.preproc and t.consumes.all? { |k| @content.key? k }
          others = @content.values_at(*t.consumes)
          begin
            tmp = t.preproc.call others
            tmp = [tmp] unless tmp.is_a? Array
            raw = tmp
            del += t.consumes
          rescue Params::Registry::Error => e
            errors[t.id] = e
          end
        end

        # if this actually goes here then there's a bug in the perl one
        next if raw.empty? and not force

        # now we use the template to process it
        begin
          tmp = t.process(*raw)
          # warn "#{t.id} => #{tmp.inspect}"
          @content[t.id] = tmp if !tmp.nil? or t.empty?
        rescue Params::Registry::Error => e
          errors[t.id] = e
        end

        # now we test for conflicts
        if !errors.key?(t.id) and !t.conflicts.empty?
          conflicts = @content.keys & t.conflicts - del.to_a
          errors[t.id] = Params::Registry::Error.new "" unless conflicts.empty?
        end

        # now we handle the complement
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
    param = @registry.templates.canonical(param) or return
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
  end

  # Taxidermy this object as an ordinary hash.
  #
  # @return [Hash] basically the same thing, minus its metadata.
  #
  def to_h
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
  end
end
