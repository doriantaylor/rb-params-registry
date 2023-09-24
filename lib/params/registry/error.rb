# frozen_string_literal: true

require_relative 'version'
require_relative 'types'

# We assume all errors are argument errors
class Params::Registry::Error < ArgumentError

  def initialize message, context: nil, value: nil
    @context = context
    @value   = value
    super message
  end

  # Errors for when nothing can be done with the lexical value of the input
  class Syntax < self
  end

  # Errors for when the syntax checks out but the value doesn't
  # conform empirically
  class Empirical < self
  end

  class Cardinality < Empirical
  end

  # A correctable error
  class Correction < Empirical
    def initialize message, context: nil, value: nil, nearest: nil
      @nearest = nearest
      super message, context: context, value: value
    end
  end

  # Errors for when there is a missing dependency
  class Dependency < Empirical
    def initialize message, context: nil, value: nil, others: nil
      @others = Types::Array[others]
      super message, context: context, value: value, others: others
    end
  end

  # Errors for when there is an actual conflict between parameters
  class Conflict < Dependency
  end
end
