require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#tainted?" do
  ruby_version_is ''...'2.7' do
    it "returns true if Object is tainted" do
      o = mock('o')
      p = mock('p')
      p.taint
      o.should_not.tainted?
      p.should.tainted?
    end
  end
end
