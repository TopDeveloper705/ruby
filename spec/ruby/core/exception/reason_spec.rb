require_relative '../../spec_helper'

describe "LocalJumpError#reason" do
  def get_me_a_return
    Proc.new { return 42 }
  end
  -> { get_me_a_return.call }.should raise_error(LocalJumpError) { |e|
    e.reason.should == :return
  }
end
