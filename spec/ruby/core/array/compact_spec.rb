require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#compact" do
  it "returns a copy of array with all nil elements removed" do
    a = [1, 2, 4]
    a.compact.should == [1, 2, 4]
    a = [1, nil, 2, 4]
    a.compact.should == [1, 2, 4]
    a = [1, 2, 4, nil]
    a.compact.should == [1, 2, 4]
    a = [nil, 1, 2, 4]
    a.compact.should == [1, 2, 4]
  end

  it "does not return self" do
    a = [1, 2, 3]
    a.compact.should_not equal(a)
  end

  it "does not return subclass instance for Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3, nil].compact.should be_an_instance_of(Array)
  end

  ruby_version_is ''...'2.7' do
    it "does not keep tainted status even if all elements are removed" do
      a = [nil, nil]
      a.taint
      a.compact.tainted?.should be_false
    end

    it "does not keep untrusted status even if all elements are removed" do
      a = [nil, nil]
      a.untrust
      a.compact.untrusted?.should be_false
    end
  end
end

describe "Array#compact!" do
  it "removes all nil elements" do
    a = ['a', nil, 'b', false, 'c']
    a.compact!.should equal(a)
    a.should == ["a", "b", false, "c"]
    a = [nil, 'a', 'b', false, 'c']
    a.compact!.should equal(a)
    a.should == ["a", "b", false, "c"]
    a = ['a', 'b', false, 'c', nil]
    a.compact!.should equal(a)
    a.should == ["a", "b", false, "c"]
  end

  it "returns self if some nil elements are removed" do
    a = ['a', nil, 'b', false, 'c']
    a.compact!.should equal a
  end

  it "returns nil if there are no nil elements to remove" do
    [1, 2, false, 3].compact!.should == nil
  end

  ruby_version_is ''...'2.7' do
    it "keeps tainted status even if all elements are removed" do
      a = [nil, nil]
      a.taint
      a.compact!
      a.tainted?.should be_true
    end

    it "keeps untrusted status even if all elements are removed" do
      a = [nil, nil]
      a.untrust
      a.compact!
      a.untrusted?.should be_true
    end
  end

  it "raises a FrozenError on a frozen array" do
    -> { ArraySpecs.frozen_array.compact! }.should raise_error(FrozenError)
  end
end
