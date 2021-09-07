# encoding: utf-8
# frozen_string_literal: true

require "optparse"
require "rbconfig"
require "leakchecker"

##
# Minimal (mostly drop-in) replacement for test-unit.
#
# :include: README.txt

module MiniTest

  def self.const_missing name # :nodoc:
    case name
    when :MINI_DIR then
      msg = "MiniTest::MINI_DIR was removed. Don't violate other's internals."
      warn "WAR\NING: #{msg}"
      warn "WAR\NING: Used by #{caller.first}."
      const_set :MINI_DIR, "bad value"
    else
      super
    end
  end

  ##
  # Assertion base class

  class Assertion < Exception; end

  ##
  # Assertion raised when skipping a test

  class Skip < Assertion; end

  class << self
    ##
    # Filter object for backtraces.

    attr_accessor :backtrace_filter
  end

  class BacktraceFilter # :nodoc:
    def filter bt
      return ["No backtrace"] unless bt

      new_bt = []

      unless $DEBUG then
        bt.each do |line|
          break if line =~ /lib\/minitest/
          new_bt << line
        end

        new_bt = bt.reject { |line| line =~ /lib\/minitest/ } if new_bt.empty?
        new_bt = bt.dup if new_bt.empty?
      else
        new_bt = bt.dup
      end

      new_bt
    end
  end

  self.backtrace_filter = BacktraceFilter.new

  def self.filter_backtrace bt # :nodoc:
    backtrace_filter.filter bt
  end

  class Unit # :nodoc:
    VERSION = "4.7.5" # :nodoc:

    attr_accessor :report, :failures, :errors, :skips # :nodoc:
    attr_accessor :assertion_count                    # :nodoc:
    attr_writer   :test_count                         # :nodoc:
    attr_accessor :start_time                         # :nodoc:
    attr_accessor :help                               # :nodoc:
    attr_accessor :verbose                            # :nodoc:
    attr_writer   :options                            # :nodoc:

    ##
    # :attr:
    #
    # if true, installs an "INFO" signal handler (only available to BSD and
    # OS X users) which prints diagnostic information about the test run.
    #
    # This is auto-detected by default but may be overridden by custom
    # runners.

    attr_accessor :info_signal

    ##
    # Lazy accessor for options.

    def options
      @options ||= {seed: 42}
    end

    @@installed_at_exit ||= false
    @@out = $stdout
    @@after_tests = []
    @@current_repeat_count = 0

    ##
    # A simple hook allowing you to run a block of code after _all_ of
    # the tests are done. Eg:
    #
    #   MiniTest::Unit.after_tests { p $debugging_info }

    def self.after_tests &block
      @@after_tests << block
    end

    ##
    # Registers MiniTest::Unit to run tests at process exit

    def self.autorun
      at_exit {
        # don't run if there was a non-exit exception
        next if $! and not $!.kind_of? SystemExit

        # the order here is important. The at_exit handler must be
        # installed before anyone else gets a chance to install their
        # own, that way we can be assured that our exit will be last
        # to run (at_exit stacks).
        exit_code = nil

        at_exit {
          @@after_tests.reverse_each(&:call)
          exit false if exit_code && exit_code != 0
        }

        exit_code = MiniTest::Unit.new.run ARGV
      } unless @@installed_at_exit
      @@installed_at_exit = true
    end

    ##
    # Returns the stream to use for output.

    def self.output
      @@out
    end

    ##
    # Sets MiniTest::Unit to write output to +stream+.  $stdout is the default
    # output

    def self.output= stream
      @@out = stream
    end

    ##
    # Tells MiniTest::Unit to delegate to +runner+, an instance of a
    # MiniTest::Unit subclass, when MiniTest::Unit#run is called.

    def self.runner= runner
      @@runner = runner
    end

    ##
    # Returns the MiniTest::Unit subclass instance that will be used
    # to run the tests. A MiniTest::Unit instance is the default
    # runner.

    def self.runner
      @@runner ||= self.new
    end

    ##
    # Return all plugins' run methods (methods that start with "run_").

    def self.plugins
      @@plugins ||= (["run_tests"] +
                     public_instance_methods(false).
                     grep(/^run_/).map { |s| s.to_s }).uniq
    end

    ##
    # Return the IO for output.

    def output
      self.class.output
    end

    def puts *a  # :nodoc:
      output.puts(*a)
    end

    def print *a # :nodoc:
      output.print(*a)
    end

    def test_count # :nodoc:
      @test_count ||= 0
    end

    ##
    # Runner for a given +type+ (eg, test vs bench).

    def self.current_repeat_count
      @@current_repeat_count
    end

    def _run_anything type
      suites = TestCase.send "#{type}_suites"
      return if suites.empty?

      puts
      puts "# Running #{type}s:"
      puts

      @test_count, @assertion_count = 0, 0
      test_count = assertion_count = 0
      sync = output.respond_to? :"sync=" # stupid emacs
      old_sync, output.sync = output.sync, true if sync

      @@current_repeat_count = 0
      begin
        start = Time.now

        results = _run_suites suites, type

        @test_count      = results.inject(0) { |sum, (tc, _)| sum + tc }
        @assertion_count = results.inject(0) { |sum, (_, ac)| sum + ac }
        test_count      += @test_count
        assertion_count += @assertion_count
        t = Time.now - start
        @@current_repeat_count += 1
        unless @repeat_count
          puts
          puts
        end
        puts "Finished%s %ss in %.6fs, %.4f tests/s, %.4f assertions/s.\n" %
             [(@repeat_count ? "(#{@@current_repeat_count}/#{@repeat_count}) " : ""), type,
               t, @test_count.fdiv(t), @assertion_count.fdiv(t)]
      end while @repeat_count && @@current_repeat_count < @repeat_count &&
                report.empty? && failures.zero? && errors.zero?

      output.sync = old_sync if sync

      report.each_with_index do |msg, i|
        puts "\n%3d) %s" % [i + 1, msg]
      end

      puts
      @test_count      = test_count
      @assertion_count = assertion_count

      status
    end

    ##
    # Runs all the +suites+ for a given +type+.
    #

    def _run_suites suites, type
      suites.map { |suite| _run_suite suite, type }
    end

    ##
    # Run a single +suite+ for a given +type+.

    def _run_suite suite, type
      header = "#{type}_suite_header"
      puts send(header, suite) if respond_to? header

      filter = options[:filter] || '/./'
      filter = Regexp.new $1 if filter =~ /\/(.*)\//

      all_test_methods = suite.send "#{type}_methods"

      filtered_test_methods = all_test_methods.find_all { |m|
        filter === m || filter === "#{suite}##{m}"
      }

      leakchecker = LeakChecker.new
      if ENV["LEAK_CHECKER_TRACE_OBJECT_ALLOCATION"]
        require "objspace"
        trace = true
      end

      assertions = filtered_test_methods.map { |method|
        inst = suite.new method
        inst._assertions = 0

        print "#{suite}##{method} = " if @verbose

        start_time = Time.now if @verbose
        result =
          if trace
            ObjectSpace.trace_object_allocations {inst.run self}
          else
            inst.run self
          end

        print "%.2f s = " % (Time.now - start_time) if @verbose
        print result
        puts if @verbose
        $stdout.flush

        unless defined?(RubyVM::JIT) && RubyVM::JIT.enabled? # compiler process is wrongly considered as leak
          leakchecker.check("#{inst.class}\##{inst.__name__}")
        end

        inst._assertions
      }
      return assertions.size, assertions.inject(0) { |sum, n| sum + n }
    end

    ##
    # Record the result of a single test. Makes it very easy to gather
    # information. Eg:
    #
    #   class StatisticsRecorder < MiniTest::Unit
    #     def record suite, method, assertions, time, error
    #       # ... record the results somewhere ...
    #     end
    #   end
    #
    #   MiniTest::Unit.runner = StatisticsRecorder.new
    #
    # NOTE: record might be sent more than once per test.  It will be
    # sent once with the results from the test itself.  If there is a
    # failure or error in teardown, it will be sent again with the
    # error or failure.

    def record suite, method, assertions, time, error
    end

    def location e # :nodoc:
      last_before_assertion = ""

      return '<empty>' unless e.backtrace # SystemStackError can return nil.

      e.backtrace.reverse_each do |s|
        break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
        last_before_assertion = s
      end
      last_before_assertion.sub(/:in .*$/, '')
    end

    ##
    # Writes status for failed test +meth+ in +klass+ which finished with
    # exception +e+

    def puke klass, meth, e
      e = case e
          when MiniTest::Skip then
            @skips += 1
            return "S" unless @verbose
            "Skipped:\n#{klass}##{meth} [#{location e}]:\n#{e.message}\n"
          when MiniTest::Assertion then
            @failures += 1
            "Failure:\n#{klass}##{meth} [#{location e}]:\n#{e.message}\n"
          else
            @errors += 1
            bt = MiniTest::filter_backtrace(e.backtrace).join "\n    "
            "Error:\n#{klass}##{meth}:\n#{e.class}: #{e.message.b}\n    #{bt}\n"
          end
      @report << e
      e[0, 1]
    end

    def initialize # :nodoc:
      @report = []
      @errors = @failures = @skips = 0
      @verbose = false
      @mutex = Thread::Mutex.new
      @info_signal = Signal.list['INFO']
      @repeat_count = nil
    end

    def synchronize # :nodoc:
      if @mutex then
        @mutex.synchronize { yield }
      else
        yield
      end
    end

    def process_args args = [] # :nodoc:
      options = {}
      orig_args = args.dup

      OptionParser.new do |opts|
        opts.banner  = 'minitest options:'
        opts.version = MiniTest::Unit::VERSION

        opts.on '-h', '--help', 'Display this help.' do
          puts opts
          exit
        end

        opts.on '-s', '--seed SEED', Integer, "Sets random seed" do |m|
          options[:seed] = m.to_i
        end

        opts.on '-v', '--verbose', "Verbose. Show progress processing files." do
          options[:verbose] = true
        end

        opts.on '-n', '--name PATTERN', "Filter test names on pattern (e.g. /foo/)" do |a|
          options[:filter] = a
        end

        opts.parse! args
        orig_args -= args
      end

      unless options[:seed] then
        srand
        options[:seed] = srand % 0xFFFF
        orig_args << "--seed" << options[:seed].to_s
      end

      srand options[:seed]

      self.verbose = options[:verbose]
      @help = orig_args.map { |s| s =~ /[\s|&<>$()]/ ? s.inspect : s }.join " "

      options
    end

    ##
    # Begins the full test run. Delegates to +runner+'s #_run method.

    def run args = []
      self.class.runner._run(args)
    end

    ##
    # Top level driver, controls all output and filtering.

    def _run args = []
      args = process_args args # ARGH!! blame test/unit process_args
      self.options.merge! args

      puts "Run options: #{help}"

      self.class.plugins.each do |plugin|
        send plugin
        break unless report.empty?
      end

      return failures + errors if self.test_count > 0 # or return nil...
    rescue Interrupt
      abort 'Interrupted'
    end

    ##
    # Runs test suites matching +filter+.

    def run_tests
      _run_anything :test
    end

    ##
    # Writes status to +io+

    def status io = self.output
      format = "%d tests, %d assertions, %d failures, %d errors, %d skips"
      io.puts format % [test_count, assertion_count, failures, errors, skips]
    end

  end # class Unit
end # module MiniTest
