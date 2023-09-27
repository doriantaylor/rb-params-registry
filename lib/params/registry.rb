# frozen_string_literal: true

require_relative 'registry/version'
require_relative 'registry/error'
require_relative 'registry/template'

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

  # This class represents a parsed instance of a set of parameters. It
  # is intended to be used like a {::Hash}, and, among other things,
  # manages the serialization of the parameters back into a normalized
  # query string.
  #
  class Instance

    def initialize registry, struct
    end

    def to_s
    end
  end

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
    # @return [Params::Registry::Template] the template.
    #
    def [] id
      @templates[id] || @aliases[id]
    end

    # Assign a template to the main registry.
    #
    # @param id [Object]
    # @param template [Hash{Symbol => Object}]
    #
    # @return [Params::Registry::Template] the new template, assigned to
    #  the registry.
    #
    def []= id, spec
      case spec
      when nil, id
        template = registry.templates[id]
        raise unless template
      when Template
        raise unless registry.equal? spec.registry
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

  def templates
    @groups[nil]
  end

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

end
