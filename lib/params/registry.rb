# frozen_string_literal: true

require_relative 'registry/version'
require_relative 'registry/error'
require_relative 'registry/template'
require_relative 'registry/instance'

require 'uri'

# {Params::Registry} is intended to contain an organization-wide
# registry of reusable named parameters. The initial purpose of such a
# thing is to control the lexical representation of serialization
# schemes of, e.g., {::URI} query parameters and
# `application/x-www-form-urlencoded` Web form input, such that they
# can be _round-tripped_ from a canonicalized string representation to
# a processed, in-memory representation and back.
#
class Params::Registry

  # A group is an identifiable sequence of parameters.
  class Group
    # Create a new group.
    #
    # @param registry [Params::Registry] the registry
    #
    def initialize registry, id, templates: nil
      @id        = id
      @registry  = registry
      @templates = {} # main mapping
      @aliases   = {} # alternate mapping
      @ranks     = {} # internal ranking for dependencies

      templates = (Types::Array|Types::TemplateMap)[templates]

      # use the internal subscript assignment
      templates.each { |t, spec| self[t] = spec || t }
    end

    # !@attribute [r] id
    #  @return [Object] the identifier of the group.
    #
    # !@attribute [r] registry
    #  @return [Params::Registry] the associated registry.

    attr_reader :id, :registry

    # Retrieve a template.
    #
    # @param id [Object] the template identifier, either canonical or an alias.
    #
    # @return [Params::Registry::Template, nil] the template, if one is found.
    #
    def [] id
      @templates[id] || @aliases[id]
    end

    # Add a parameter template to the group. The `spec` can be a
    # template specification, or it can be an already-instantiated
    # template, or it can be the same as `id`, or it can be `nil`. In
    # the first case, the template will be created and added to the
    # registry, replacing any template with the same ID. In the case
    # that it's a {Params::Registry::Template} instance, its ID must
    # match `id` and it must come from the same registry as the
    # group. In the latter two cases, the parameter is retrieved from
    # the registry, raising an exception if not.
    #
    # @param id [Object] the template's canonical identifier.
    # @param spec [Hash{Symbol => Object}, Params::Registry::Template, nil]
    #  the template specification, as described above.
    #
    # @return [Params::Registry::Template] the new template, assigned to
    #  the registry.
    #
    def []= id, spec
      case spec
      when nil, id
        template = registry.templates[id]
        raise ArgumentError, "Could not find template #{id}" unless template
      when Template
        raise ArgumentError,
          "Template #{id} supplied from some other registry" unless
          registry.equal? spec.registry
        raise ArgumentError,
          "Identifier #{id} does not match template (#{spec.id})" unless
          id == spec.id
        template = spec
      else
        Types::Hash[spec]
        template = registry.template_class.new registry, id, **spec
      end

      # make sure we aren't calling ourselves
      registry.templates[id] = template unless registry.templates.equal? self

      # okay now actually assign
      @templates[id] = template

      # then map all the aliases and crap
      @aliases[template.slug] = template if template.slug
      # we use a conditional assign here since aliases take a lower priority
      template.aliases.each { |a| @aliases[a] ||= template }

      # now we compute the rank, but first we need the dependencies
      deps = template.depends.map do |t|
        registry.templates[t]
      end.compact.map(&:id)

      # warn deps.inspect

      # XXX this does not do cycles; we should really do cycles.
      rank = @ranks.values_at(*deps).compact.max
      @ranks[id] = rank.nil? ? 0 : rank + 1

      # warn template.id
      template
    end

    # Return whether the group has a given key.
    #
    # @return [false, true] what I said.
    #
    def key? id
      !!self[id]
    end

    # Return the canonical template identifiers.
    #
    # @return [Array] the keys.
    #
    def keys ; @templates.keys; end

    # Return the template entries, in order.
    #
    # @return [Array<Params::Registry::Template>] the templates.
    #
    def templates ; @templates.values; end

    # Assign a new sequence of templates to the group.
    #
    # @param templates [Array, Hash] the set of templates
    #
    # @return [Array, Hash] whatever was passed
    #  in because Ruby ignores the output
    #
    def templates= templates
      templates = templates.to_a if templates.is_a? Hash

      raise ArgumentError,
        "Don't know what to do with #{templates.class}" unless
        templates.respond_to? :to_a

      # empty out the actual instance member
      @templates.clear

      # this should destructure appropriately (XXX MAYBE???) and also
      # use the overloaded subscript assignment method
      templates.to_a.each { |id, spec| self[id] = spec || id }

      # now return the new members
      @templates.values
    end

    # Return the canonical identifier for the template.
    #
    # @param id [Object] the identifier, canonical or otherwise.
    #
    # @return [Object, nil] the canonical identifier, if found.
    #
    def canonical id
      return id if @templates.key? id
      @aliases[id].id if @aliases.key? id
    end

    # Return an array of arrays of templates sorted by rank. A higher
    # rank means a parameter depends on one or more parameters with a
    # lower rank.
    #
    # @return [Array<Hash{Object => Params::Registry::Template}>] the
    #  ranked parameter templates.
    #
    def ranked
      # warn @ranks.inspect

      out = Array.new((@ranks.values.max || -1) + 1) { {} }

      # warn out.inspect

      @templates.values.reject do |t|
        # skip the complement as it's handled out of band
        t.equal? registry.complement
      end.each { |t| out[@ranks[t.id]][t.id] = t }

      out
    end

    # Delete a template from the group.
    #
    # @param id [Object] the canonical identifier for the template, or an alias.
    #
    # @return [Params::Registry::Template, nil] the removed template,
    #  if there was one present to be removed.
    #
    def delete id
      # first we have to find it
      return unless template = self[id]

      @templates.delete template.id
      @ranks.delete template.id
      @aliases.delete template.slug if template.slug

      # XXX i feel like we should try to find other parameters that
      # may have an alias that's the same as the one we just deleted
      # and give (the first matching one) the now-empty slot, but
      # that's not urgent so i'll leave it for now.
      template.aliases.each do |a|
        @aliases.delete a if template.equal? @aliases[a]
      end

      # if we are the main registry group we have to do extra stuff
      if registry.templates.equal? self
        registry.groups.each { |g| g.delete template.id }
      end

      # this leaves us with an unbound template which i gueessss we
      # could reinsert?
      template
    end

    # Return a suitable representation for debugging.
    #
    # @return [String] the object.
    #
    def inspect
      "#<#{self.class}: #{id} {#{keys.join ', '}}>"
    end

    # Process the parameters and return a {Params::Registry::Instance}.
    #
    # @param params
    #  [String, URI, Hash{#to_sym => Array}, Array<Array<(#to_sym, Object)>>]
    #  the parameter set, in a dizzying variety of inputs.
    #
    # @return [Params::Registry::Instance] the instance.
    #
    def process params, defaults: false, force: false
      registry.instance_class.new self, Types::Input[params],
        defaults: defaults, force: force
    end

  end

  private

  # The complement can be either an identifier or it can be a
  # (partial) template spec with one additional `:id` member.
  def coerce_complement complement
    complement ||= :complement
    # complement can be a name, or it can be a structure which is
    # merged with the boilerplate below.
    if complement.is_a? Hash
      complement = Types::TemplateSpec[complement]
      raise ArgumentError, 'Complement hash is missing :id' unless
        complement.key? :id
      spec = complement.except :id
      complement = complement[:id]
    else
      spec = {}
    end

    # for the closures
    ts = templates

    # we always want these closures so we steamroll over whatever the
    # user might have put in these slots
    spec.merge!({
      composite: Types::Set.constructor { |set|
        # warn "heyooo #{set.inspect}"
        raise Dry::Types::ConstraintError,
          "#{complement} has values not found in templates" unless
            set.all? { |t| ts.select { |_, x| x.complement? }.key? t }
        Set[*set]
      },
      unwind: -> set {
        # XXX do we want to sort this lexically or do we want it in
        # the same order as the keys?
        [set.to_a.map { |t| t = ts[t]; (t.slug || t.id).to_s }.sort, false]
      }
    })

    [complement, spec]
  end

  public

  # Initialize the registry. You will need to supply a set of specs
  # that will become {::Params::Registry::Template} objects. You can
  # also supply groups which you can use how you like.
  #
  # Parameters can be defined within groups or separately from them.
  # This allows subsets of parameters to be easily hived off from the
  # main {Params::Registry::Instance}.
  #
  # There is a special meta-parameter `:complement` which takes as its
  # values the names of other parameters. This is intended to be used
  # to signal that the parameters so named, assumed to be some kind of
  # composite, like a {::Set} or {::Range}, are to be complemented or
  # negated. The purpose of this is, for instance, if you want to
  # express a parameter that is a set with many values, and rather
  # than having to enumerate each of the values in something like a
  # query string, you only have to enumerate the values you *don't*
  # want in the set.
  #
  # @note The complement parameter is always set (last), and its
  #  identifier defaults, unsurprisingly, to `:complement`. This can
  #  be overridden by specifying an identifier you prefer. If you want
  #  a slug that is distinct from the canonical identifier, or if you
  #  want aliases, pass in a spec like this: `{ id:
  #  URI('https://my.schema/parameters#complement'), slug:
  #  :complement, aliases: %i[invert negate] }`
  #
  # @param templates [Hash] the hash of template specifications.
  # @param groups [Hash, Array] the hash of groups.
  # @param complement [Object, Hash] the identifier for the parameter
  #  for complementing composites, or otherwise a partial specification.
  #
  def initialize templates: nil, groups: nil, complement: nil
    # initialize the object state with an empty default group
    @groups = { nil => Group.new(self, nil) }

    # coerce these guys
    templates = Types::TemplateMap[templates]
    groups    = Types::GroupMap[groups]

    # now load templates
    templates.each { |id, spec| self.templates[id] = spec }

    # now load groups
    groups.each { |id, specs| self[id] = specs }

    # now deal with complement
    cid, cspec = coerce_complement complement
    self.templates[cid] = cspec # XXX note leaky abstraction
    # warn wtf.inspect
    @complement = self.templates[cid]
  end

  # @!attribute [r] complement
  # The `complement` template.
  # @return [Params::Registry::Template]
  attr_reader :complement

  # Retrieve a group.
  #
  # @return [Params::Registry::Group] the group.
  #
  def [] id
    @groups[id]
  end

  # Assign a group.
  #
  # @return [Params::Registry::Group] the new group.
  #
  def []= id, spec
    # the null id is special; you can't assign to it
    id = Types::NonNil[id]

    @groups[id] = group_class.new self, id, templates: spec
  end

  # Retrieve the names of the groups.
  #
  # @return [Array] the group names.
  #
  def keys
    @groups.keys.reject(&:nil?)
  end

  # Retrieve the groups themselves.
  #
  # @return [Array<Params::Registry::Group>] the groups.
  #
  def groups
    @groups.values_at(*keys)
  end

  # Retrieve the master template group.
  #
  # @return [Params::Registry::Group] the master group.
  #
  def templates
    # XXX is this dumb? would it be better off as its own member?
    @groups[nil]
  end

  # Process the parameters and return a {Params::Registry::Instance}.
  #
  # @param params
  #  [String, URI, Hash{#to_sym => Array}, Array<Array<(#to_sym, Object)>>]
  #  the parameter set, in a dizzying variety of inputs.
  #
  # @return [Params::Registry::Instance] the instance.
  #
  def process params, defaults: false, force: false
    instance_class.new self, Types::Input[params],
      defaults: defaults, force: force
  end

  # Refresh any stateful elements of the templates.
  #
  # @return [self]
  #
  def refresh!
    templates.templates.each { |t| t.refresh! }

    self
  end

  # @!group Quasi-static methods to override in subclasses

  # The template class to use. Override this in a subclass if you want
  # to use a custom one.
  #
  # @return [Class] the template class, {Params::Registry::Template}.
  #
  def template_class
    Template
  end

  # The instance class to use. Override this in a subclass if you want
  # to use a custom one.
  #
  # @return [Class] the instance class, {Params::Registry::Instance}.
  #
  def instance_class
    Instance
  end

  # The group class to use. Override this in a subclass if you want
  # to use a custom one.
  #
  # @return [Class] the group class, {Params::Registry::Group}.
  #
  def group_class
    Group
  end

  # @!endgroup
end
