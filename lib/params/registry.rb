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

      # amke sure we aren't calling ourselves
      registry.templates[id] = template unless registry.templates.equal? self

      # okay now actually assign
      @templates[id] = template

      # then map all the aliases and crap
      @aliases[template.slug] = template if template.slug
      # we use a conditional assign here since aliases take a lower priority
      template.aliases.each { |a| @aliases[a] ||= template }

      template
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
    def inspect
      "<#{self.class}: #{id} {#{keys.join ', '}}>"
    end

  end

  # Initialize the registry.
  #
  # @param templates [Hash] the hash of template specifications
  # @param groups [Hash, Array] the hash of groups
  # @param complement [Object]
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
  end

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

    @groups[id] = Group.new self, id, templates: spec
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
  def process params
    instance_class.new self, Types::Input[params]
  end

  # Refresh any stateful elements of the templates.
  #
  # @return [void]
  #
  def refresh!
    templates.each { |t| t.refresh! }
    nil
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
