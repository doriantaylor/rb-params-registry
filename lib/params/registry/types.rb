# frozen_string_literal: true

require_relative "version"

require 'dry-types' # let's try to use this and not hate it
require 'set'       # for some reason Set is not in the kernel but Range is
require 'date'      # includes DateTime
require 'time'      # ruby has Time and DateTime to be confusing
require 'uri'

# All the type coercions used in {Params::Registry}.
module Params::Registry::Types
  include Dry.Types(default: :coercible)

  # Syntactic sugar for retrieving types in the library.
  #
  # @param const [#to_sym] The type (name).
  #
  # @return [Dry::Types::Type] The type instance.
  #
  def self.[] const
    return const if const.is_a? Dry::Types::Type
    begin
      const_get const.to_s.to_sym
    rescue NameError
      raise ArgumentError, "No type named #{const}"
    end
  end

  # Can be anything, as long as it isn't `nil`.
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

  # For some reason there isn't a stock `Proc` type.
  Proc = self.Instance(::Proc)

  # @!group A bunch of integer types

  # The problem with Kernel.Integer is that if a string representing
  # a number begins with a zero it's treated as octal, so we have to
  # compensate for that.
  DecimalInteger = Nominal::Integer.constructor do |i|
    i.is_a?(::Numeric) ? i.to_i : ::Kernel.Integer(i.to_s, 10)
  end

  # `xsd:nonPositiveInteger`
  NonPositiveInteger = DecimalInteger.constrained lteq: 0
  # `xsd:nonNegativeInteger`
  NonNegativeInteger = DecimalInteger.constrained gteq: 0
  # `xsd:positiveInteger`
  PositiveInteger    = DecimalInteger.constrained gt: 0
  # `xsd:negativeInteger`
  NegativeInteger    = DecimalInteger.constrained lt: 0

  # @!group Stringy stuff, à la XSD plus some others

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

  # This one is symbol-*ish*
  Symbolish = self.Constructor(::Object) do |x|
    if [::String, ::Symbol].any? { |c| x.is_a? c }
      Symbol[x]
    else
      x
    end
  end

  # @!group Dates & Times

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
    when (DecimalInteger[x] rescue nil) then ::Time.at(DecimalInteger[x])
    else ::Time.parse x
    end
  end

  # @!group Composite types not already defined

  # {::Set}
  Set = self.Constructor(::Set) { |x| ::Set[*x] }

  # {::Range}
  Range = self.Constructor(::Range) { |x| ::Range.new(*x.take(2)) }

  # The registry itself
  Registry = self.Instance(::Params::Registry)

  # Templates

  TemplateSpec = Hash.map(Symbol, Strict::Any)

  TemplateMap = Hash|Hash.map(NonNil, TemplateSpec)

  # Groups
  GroupMap = Hash|Hash.map(NonNil, Array|TemplateMap)

  Input = self.Constructor(::Hash) do |input|
    input = input.query.to_s if input.is_a? ::URI
    input = ::URI.decode_www_form input if input.is_a? ::String

    case input
    when ::Hash then Hash.map(Symbolish, Array.of(String))[input]
    when ::Array
      input.reduce({}) do |out, pair|
        k, *v = Strict::Array.constrained(min_size: 2)[pair]
        (out[Symbolish[k]] ||= []).push(*v)
        out
      end
    else
      raise Dry::Types::CoercionError,
        "not sure what to do with #{input.inspect}"
    end
  end

  # @!endgroup
end
