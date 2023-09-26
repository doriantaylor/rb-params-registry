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
      registry = Params::Registry.new templates: { test: { } }
      expect(registry.templates[:test]).to be_a(Params::Registry::Template)
    end

    it 'initializes with a group' do
      registry = Params::Registry.new templates: { test: { } },
        groups: { g1: %i[test] }

      expect(registry[:g1]).to be_a(Params::Registry::Group)
      expect(registry[:g1][:test]).to be_a(Params::Registry::Template)
      expect(registry[nil][:test]).to be_equal(registry[:g1][:test])
    end

    it 'initializes with a group that sets a parameter' do
      registry = Params::Registry.new groups: { g1: { test: { } } }

      expect(registry[:g1][:test]).to be_equal(registry.templates[:test])
    end
  end
end
