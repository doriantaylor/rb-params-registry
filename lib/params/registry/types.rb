# frozen_string_literal: true

require_relative "version"

require 'dry-types' # let's try to use this and not hate it
require 'set'       # for some reason Set is not in the kernel but Range is
require 'date'      # includes DateTime
require 'time'      # ruby has Time and DateTime to be confusing

module Params::Registry::Types
  include Dry.Types(default: :coercible)

  # Syntactic sugar for retrieving types in the library.
  #
  # @param const [#to_sym] The type name
  #
  # @return [Dry::Types::Type] The type instance
  #
  def self.[] const
    return const if const.is_a? Dry::Types::Type
    begin
      const_get const.to_s.to_sym
    rescue NameError
      raise ArgumentError, "No type named #{const}"
    end
  end

  NonNil = Strict::Any.constrained not_eql: nil

  # Gotta have a coercible boolean (which doesn't come stock for some reason)
  Bool = Nominal::Bool.constructor do |x|
    case x.to_s.strip
    when /\A(1|true|on|yes)\Z/i then true
    when /\A(0|false|off|no|)\Z/i then false
    else
      raise Dry::Types::CoercionError, "#{x} can't be coerced to true or false"
    end
  end

  Proc = self.Instance(Proc)

  Registry = self.Instance(::Params::Registry)

  # @group A bunch of integer types

  # The problem with Kernel.Integer is that if a string representing
  # a number begins with a zero it's treated as octal, so we have to
  # compensate for that.
  Base10Integer = Nominal::Integer.constructor do |i|
    i.is_a?(::Numeric) ? i.to_i : ::Kernel.Integer(i.to_s, 10)
  end

  NonPositiveInteger = Base10Integer.constrained lteq: 0
  NonNegativeInteger = Base10Integer.constrained gteq: 0
  PositiveInteger    = Base10Integer.constrained gt: 0
  NegativeInteger    = Base10Integer.constrained lt: 0

  # @group Stringy stuff, à la XSD plus some others

  # This is `xsd:normalizedString`.
  NormalizedString = Nominal::String.constructor do |s|
    s.to_s.gsub(/[\t\r\n]/, ' ')
  end

  # This is `xsd:token`.
  Token = NormalizedString.constructor { |s| s.tr_s(' ', ' ').strip }

  # Coerce an `xsd:token` into a {::Symbol}.
  Symbol = Token.constructor { |t| t.to_sym }

  # Coerce an `xsd:token` into a symbol with all lower-case letters.
  LCSymbol = Token.constructor { |t| t.downcase.to_sym }

  # Do the same but with upper-case letters.
  UCSymbol = Token.constructor { |t| t.upcase.to_sym }

  # Create a symbol with all whitespace and underscores turned to hyphens.
  HyphenSymbol = Token.constructor { |t| t.tr_s(' _', ?-).to_sym }

  # Do the same but with all lower-case letters.
  LCHyphenSymbol = HyphenSymbol.constructor { |s| s.to_s.downcase.to_sym }

  # Do the same but with all upper-case letters.
  UCHyphenSymbol = HyphenSymbol.constructor { |s| s.to_s.upcase.to_sym }

  # Create a symbol with all whitespace and hyphens turned to underscores.
  UnderscoreSymbol = Token.constructor { |t| t.tr_s(' -', ?_).to_sym }

  # Do the same but with all lower-case letters.
  LCUnderscoreSymbol = UnderscoreSymbol.constructor do |s|
    s.to_s.downcase.to_sym
  end

  # Do the same but with all upper-case letters.
  UCUnderscoreSymbol = UnderscoreSymbol.constructor do |s|
    s.to_s.upcase.to_sym
  end

  # @group Dates & Times

  # Ye olde {::Date}
  Date = self.Constructor(::Date) do |x|
    case x
    when ::Array then ::Date.new(*x.take(3))
    else ::Date.parse x
    end
  end

  # And {::DateTime}
  DateTime = self.Constructor(::DateTime) do |x|
    ::DateTime.parse x
  end

  # Aaand {::Time}
  Time = self.Constructor(::Time) do |x|
    case x
    when ::Array then ::Time.new(*x)
    when (Base10Integer[x] rescue nil) then ::Time.at(Base10Integer[x])
    else ::Time.parse x
    end
  end

  # @group Composite types not already defined

  # {::Set}
  Set = self.Constructor(::Set) { |x| ::Set[*x] }

  # {::Range}
  Range = self.Constructor(::Range) { |x| ::Range.new(*x.take(2)) }

end
