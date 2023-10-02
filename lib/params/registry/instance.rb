# frozen_string_literal: true

require_relative 'types'

# This class represents a parsed instance of a set of parameters. It
# is intended to be used like a {::Hash}, and, among other things,
# manages the serialization of the parameters back into a normalized
# query string.
#
class Params::Registry::Instance
  private

  Types = Params::Registry::Types

  public

  # Make a new instance.
  #
  # @param registry [Params::Registry] the registry

  # @param struct [Hash{Symbol => Array<String>}] something that
  #  resembles the output of `URI.decode_www_form`.
  #
  def initialize registry, struct, extra = nil
  end

  # Retrieve the processed value for a parameter.
  #
  # @param param [Object, #to_sym] the parameter identifier, or
  #  slug, or alias.
  #
  # @return [Object, Array, nil] the value, if present.
  #
  def [] param
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
