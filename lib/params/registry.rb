# frozen_string_literal: true

require_relative 'registry/version'
require_relative 'registry/error'
require_relative 'registry/template'

# Define an organization-wide registry for parameters.
#
class Params::Registry

  def initialize templates: nil, groups: nil
  end

  # This class represents a parsed instance of a set of parameters. It
  # is intended to be used like a {::Hash}, and, among other things,
  # manages the serialization of the parameters back into a normalized
  # query string.
  class Instance

    def initialize registry
    end

    def to_s
    end
  end

  class Group < self

    def initialize registry, id
    end
  end
end
