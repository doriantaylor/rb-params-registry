# frozen_string_literal: true

RSpec.describe Params::Registry do
  context 'the basics' do
    it 'has a version number' do
      expect(Params::Registry::VERSION).not_to be nil
    end

    it 'initializes empty' do
      expect(Params::Registry.new).to be
    end

    it 'initializes with a parameter' do
      registry = Params::Registry.new templates: { test: {} }
      expect(registry.templates[:test]).to be_a(Params::Registry::Template)
    end

    it 'initializes with a group' do
      registry = Params::Registry.new templates: { test: { } },
        groups: { g1: %i[test] }

      expect(registry[:g1]).to be_a(Params::Registry::Group)
      expect(registry[:g1][:test]).to be_a(Params::Registry::Template)
      expect(registry[nil][:test]).to be_equal(registry[:g1][:test])
      expect(registry.keys).to eq(%i[g1])
      expect(registry.groups).to eq([registry[:g1]])
    end

    it 'initializes with a group that sets a parameter' do
      registry = Params::Registry.new groups: { g1: { test: { } } }

      expect(registry[:g1][:test]).to be_equal(registry.templates[:test])
    end

    it 'initializes with a group that reuses a parameter' do
      registry = Params::Registry.new templates: { test: {} },
        groups: { g1: %i[test] }

      expect(registry[:g1][:test]).to be_equal(registry.templates[:test])
    end

    it 'affords the removal of templates' do
      registry = Params::Registry.new templates: { test: { slug: :other } },
        groups: { g1: %i[test] }

      # removing a template also removes it from any groups
      t = registry.templates.delete :test
      expect(registry[:g1][:test]).to be_nil
      # removing it also ensures that it isn't sticking around in aliases
      expect(registry.templates[:other]).to be_nil
    end
  end

  context 'how about actually parsing something' do
    subject { Params::Registry.new templates: { test: { slug: :other } } }
    it 'generates a simple instance' do
      expect(subject.process 'test=foo').to be_a Params::Registry::Instance
    end

    it 'generates a grouped instance' do
    end

    it 'shares parameters among groups' do
    end

    it 'correctly complains about conflicts' do
    end

    # note: "complex" is distinct from "composite"
    it 'consumes elementary parameters to construct complex ones' do
      registry = Params::Registry.new templates: {
        year: {
          type: Params::Registry::Types::Integer,
        },
        month: {
          type: Params::Registry::Types::Integer.constrained(gt: 0, lteq: 12),
        },
        day: {
          type: Params::Registry::Types::Integer.constrained(gt: 0, lteq: 31),
        },
        date: {
          type: Params::Registry::Types::Date,
          consumes: %i[year month day],
          preproc: -> others { '%04d-%02d-%02d' % others },
        },
      }

    end
  end
end
