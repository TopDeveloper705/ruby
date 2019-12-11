require_relative '../fixtures/classes'

describe :thread_to_s, shared: true do
  sep = " "
  ruby_version_is(''..."2.7"){ sep = '@' }

  it "returns a description including file and line number" do
    ruby_version_is(''...'2.5') do
      # Thread#to_s is not same as Thread#inspect until Ruby 2.4.
      skip if @method == :to_s
    end

    Thread.new { "hello" }.send(@method).should =~ /^#<Thread:([^ ]*?)#{sep}#{Regexp.escape __FILE__}:#{__LINE__ } \w+>$/
  end

  it "has a binary encoding" do
    Thread.new { "hello" }.send(@method).encoding.should == Encoding::BINARY
  end

  it "can check it's own status" do
    ThreadSpecs.status_of_current_thread.inspect.should include('run')
  end

  it "describes a running thread" do
    ThreadSpecs.status_of_running_thread.inspect.should include('run')
  end

  it "describes a sleeping thread" do
    ThreadSpecs.status_of_sleeping_thread.inspect.should include('sleep')
  end

  it "describes a blocked thread" do
    ThreadSpecs.status_of_blocked_thread.inspect.should include('sleep')
  end

  it "describes a completed thread" do
    ThreadSpecs.status_of_completed_thread.inspect.should include('dead')
  end

  it "describes a killed thread" do
    ThreadSpecs.status_of_killed_thread.inspect.should include('dead')
  end

  it "describes a thread with an uncaught exception" do
    ThreadSpecs.status_of_thread_with_uncaught_exception.inspect.should include('dead')
  end

  it "describes a dying sleeping thread" do
    ThreadSpecs.status_of_dying_sleeping_thread.inspect.should include('sleep')
  end

  it "reports aborting on a killed thread" do
    ThreadSpecs.status_of_dying_running_thread.inspect.should include('aborting')
  end

  it "reports aborting on a killed thread after sleep" do
    ThreadSpecs.status_of_dying_thread_after_sleep.inspect.should include('aborting')
  end
end
