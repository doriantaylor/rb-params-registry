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

  context 'parsing input' do
    subject do
      Params::Registry.new templates: {
        year: {
          type: Params::Registry::Types::Integer,
          max: 1,
        },
        month: {
          type: Params::Registry::Types::Integer.constrained(gt: 0, lteq: 12),
          max: 1,
        },
        day: {
          type: Params::Registry::Types::Integer.constrained(gt: 0, lteq: 31),
          max: 1,
        },
        date: {
          type: Params::Registry::Types::Date,
          max: 1,
          consumes: %i[year month day],
          preproc: -> _, others {
            '%04d-%02d-%02d' % others.values_at(:year, :month, :day) },
        },
        test: {
          slug: :slug,
          max: 1,
        },
        boundary: {
          type: Params::Registry::Types::Integer,
          composite: Params::Registry::Types::Range,
          unwind: -> value { value.minmax },
          default: 1..100,
          # min: 2,
        },
      }, groups: {
        paginated: %i[boundary],
      }
    end

    it 'initializes an instance from a string' do
      instance = subject.process 'test=foo'
      # warn instance.to_s
      expect(instance).to be_a Params::Registry::Instance
    end

    it 'generates a grouped instance' do
      instance = subject[:paginated].process 'boundary=1&boundary=10&test=foo'
      expect(instance[:test]).to be_nil
      expect(instance.extra[:test]).to_not be_nil
    end

    it 'shares parameters among groups' do
      # TODO lol
    end

    it 'correctly complains about conflicts' do
      # TODO lol
    end

    it 'consumes elementary parameters to construct derived ones' do
      instance = subject.process 'year=2023&month=10&day=04&test=hi'
      # warn instance.to_s
      expect(instance[:date]).to be_a Date # should be single coerced value
      expect(instance[:year]).to be_nil # consumed parameters should be gone
      expect(instance.to_h(slugs: true)[:slug]).to eq('hi')
    end

    it 'handles its complement correctly' do
      expect(subject.complement).to be
    end

    # it turns out `Range` is useful for testing composites because
    # `#to_a` (the default unwind function) has obviously wrong
    # behaviour.

    context '(composite)' do
      it 'processes correctly from the template' do
        value = subject.templates[:boundary].process %w[1 10]
        expect(value).to eq(1..10)
      end
      it 'initializes from a parsed struct' do
        instance = subject.process({ boundary: 1..10 })
        expect(instance[:boundary]).to eq(1..10)
      end

      it 'initializes from a raw struct' do
        instance = subject.process({ boundary: %w[1 10] })
        expect(instance[:boundary]).to eq(1..10)
      end

      it 'initializes from a string' do
        instance = subject.process 'boundary=1&boundary=10'
        expect(instance[:boundary]).to eq(1..10)
      end

      it 'dups/clones successfully' do
        i1 = subject.process({ boundary: 1..10 })
        i2 = i1.dup

        expect(i2[:boundary]).to eq(1..10)
      end

      it 'takes assignments correctly' do
        instance = subject.process({ boundary: 1..10 })
        instance[:boundary] = 1..50
        expect(instance[:boundary]).to eq(1..50)
      end
    end

    context '(serialization)' do
      it 'serializes correctly' do
        instance = subject.process 'test=hi'
        expect(instance.to_s).to eq('slug=hi')
      end

      it 'omits defaults unless explicitly told to render them' do
        instance = subject.process 'test=hi'
        expect(instance[:boundary]).to eq(1..100)
        expect(instance.to_s defaults: true).to eq('slug=hi&boundary=1&boundary=100')
        expect(instance.to_s defaults: :boundary).to eq('slug=hi&boundary=1&boundary=100')
        expect(instance.to_s defaults: %i[boundary]).to eq('slug=hi&boundary=1&boundary=100')
      end
    end
  end
end
