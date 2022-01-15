# -*- coding: us-ascii -*-
# frozen_string_literal: true
# = ERB -- Ruby Templating
#
# Author:: Masatoshi SEKI
# Documentation:: James Edward Gray II, Gavin Sinclair, and Simon Chiang
#
# See ERB for primary documentation and ERB::Util for a couple of utility
# routines.
#
# Copyright (c) 1999-2000,2002,2003 Masatoshi SEKI
#
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'cgi/util'
require 'erb/version'

#
# = ERB -- Ruby Templating
#
# == Introduction
#
# ERB provides an easy to use but powerful templating system for Ruby.  Using
# ERB, actual Ruby code can be added to any plain text document for the
# purposes of generating document information details and/or flow control.
#
# A very simple example is this:
#
#   require 'erb'
#
#   x = 42
#   template = ERB.new <<-EOF
#     The value of x is: <%= x %>
#   EOF
#   puts template.result(binding)
#
# <em>Prints:</em> The value of x is: 42
#
# More complex examples are given below.
#
#
# == Recognized Tags
#
# ERB recognizes certain tags in the provided template and converts them based
# on the rules below:
#
#   <% Ruby code -- inline with output %>
#   <%= Ruby expression -- replace with result %>
#   <%# comment -- ignored -- useful in testing %> (`<% #` doesn't work. Don't use Ruby comments.)
#   % a line of Ruby code -- treated as <% line %> (optional -- see ERB.new)
#   %% replaced with % if first thing on a line and % processing is used
#   <%% or %%> -- replace with <% or %> respectively
#
# All other text is passed through ERB filtering unchanged.
#
#
# == Options
#
# There are several settings you can change when you use ERB:
# * the nature of the tags that are recognized;
# * the binding used to resolve local variables in the template.
#
# See the ERB.new and ERB#result methods for more detail.
#
# == Character encodings
#
# ERB (or Ruby code generated by ERB) returns a string in the same
# character encoding as the input string.  When the input string has
# a magic comment, however, it returns a string in the encoding specified
# by the magic comment.
#
#   # -*- coding: utf-8 -*-
#   require 'erb'
#
#   template = ERB.new <<EOF
#   <%#-*- coding: Big5 -*-%>
#     \_\_ENCODING\_\_ is <%= \_\_ENCODING\_\_ %>.
#   EOF
#   puts template.result
#
# <em>Prints:</em> \_\_ENCODING\_\_ is Big5.
#
#
# == Examples
#
# === Plain Text
#
# ERB is useful for any generic templating situation.  Note that in this example, we use the
# convenient "% at start of line" tag, and we quote the template literally with
# <tt>%q{...}</tt> to avoid trouble with the backslash.
#
#   require "erb"
#
#   # Create template.
#   template = %q{
#     From:  James Edward Gray II <james@grayproductions.net>
#     To:  <%= to %>
#     Subject:  Addressing Needs
#
#     <%= to[/\w+/] %>:
#
#     Just wanted to send a quick note assuring that your needs are being
#     addressed.
#
#     I want you to know that my team will keep working on the issues,
#     especially:
#
#     <%# ignore numerous minor requests -- focus on priorities %>
#     % priorities.each do |priority|
#       * <%= priority %>
#     % end
#
#     Thanks for your patience.
#
#     James Edward Gray II
#   }.gsub(/^  /, '')
#
#   message = ERB.new(template, trim_mode: "%<>")
#
#   # Set up template data.
#   to = "Community Spokesman <spokesman@ruby_community.org>"
#   priorities = [ "Run Ruby Quiz",
#                  "Document Modules",
#                  "Answer Questions on Ruby Talk" ]
#
#   # Produce result.
#   email = message.result
#   puts email
#
# <i>Generates:</i>
#
#   From:  James Edward Gray II <james@grayproductions.net>
#   To:  Community Spokesman <spokesman@ruby_community.org>
#   Subject:  Addressing Needs
#
#   Community:
#
#   Just wanted to send a quick note assuring that your needs are being addressed.
#
#   I want you to know that my team will keep working on the issues, especially:
#
#       * Run Ruby Quiz
#       * Document Modules
#       * Answer Questions on Ruby Talk
#
#   Thanks for your patience.
#
#   James Edward Gray II
#
# === Ruby in HTML
#
# ERB is often used in <tt>.rhtml</tt> files (HTML with embedded Ruby).  Notice the need in
# this example to provide a special binding when the template is run, so that the instance
# variables in the Product object can be resolved.
#
#   require "erb"
#
#   # Build template data class.
#   class Product
#     def initialize( code, name, desc, cost )
#       @code = code
#       @name = name
#       @desc = desc
#       @cost = cost
#
#       @features = [ ]
#     end
#
#     def add_feature( feature )
#       @features << feature
#     end
#
#     # Support templating of member data.
#     def get_binding
#       binding
#     end
#
#     # ...
#   end
#
#   # Create template.
#   template = %{
#     <html>
#       <head><title>Ruby Toys -- <%= @name %></title></head>
#       <body>
#
#         <h1><%= @name %> (<%= @code %>)</h1>
#         <p><%= @desc %></p>
#
#         <ul>
#           <% @features.each do |f| %>
#             <li><b><%= f %></b></li>
#           <% end %>
#         </ul>
#
#         <p>
#           <% if @cost < 10 %>
#             <b>Only <%= @cost %>!!!</b>
#           <% else %>
#              Call for a price, today!
#           <% end %>
#         </p>
#
#       </body>
#     </html>
#   }.gsub(/^  /, '')
#
#   rhtml = ERB.new(template)
#
#   # Set up template data.
#   toy = Product.new( "TZ-1002",
#                      "Rubysapien",
#                      "Geek's Best Friend!  Responds to Ruby commands...",
#                      999.95 )
#   toy.add_feature("Listens for verbal commands in the Ruby language!")
#   toy.add_feature("Ignores Perl, Java, and all C variants.")
#   toy.add_feature("Karate-Chop Action!!!")
#   toy.add_feature("Matz signature on left leg.")
#   toy.add_feature("Gem studded eyes... Rubies, of course!")
#
#   # Produce result.
#   rhtml.run(toy.get_binding)
#
# <i>Generates (some blank lines removed):</i>
#
#    <html>
#      <head><title>Ruby Toys -- Rubysapien</title></head>
#      <body>
#
#        <h1>Rubysapien (TZ-1002)</h1>
#        <p>Geek's Best Friend!  Responds to Ruby commands...</p>
#
#        <ul>
#            <li><b>Listens for verbal commands in the Ruby language!</b></li>
#            <li><b>Ignores Perl, Java, and all C variants.</b></li>
#            <li><b>Karate-Chop Action!!!</b></li>
#            <li><b>Matz signature on left leg.</b></li>
#            <li><b>Gem studded eyes... Rubies, of course!</b></li>
#        </ul>
#
#        <p>
#             Call for a price, today!
#        </p>
#
#      </body>
#    </html>
#
#
# == Notes
#
# There are a variety of templating solutions available in various Ruby projects.
# For example, RDoc, distributed with Ruby, uses its own template engine, which
# can be reused elsewhere.
#
# Other popular engines could be found in the corresponding
# {Category}[https://www.ruby-toolbox.com/categories/template_engines] of
# The Ruby Toolbox.
#
class ERB
  Revision = '$Date::                           $' # :nodoc: #'
  deprecate_constant :Revision

  # Returns revision information for the erb.rb module.
  def self.version
    VERSION
  end
end

#--
# ERB::Compiler
class ERB
  # = ERB::Compiler
  #
  # Compiles ERB templates into Ruby code; the compiled code produces the
  # template result when evaluated. ERB::Compiler provides hooks to define how
  # generated output is handled.
  #
  # Internally ERB does something like this to generate the code returned by
  # ERB#src:
  #
  #   compiler = ERB::Compiler.new('<>')
  #   compiler.pre_cmd    = ["_erbout=+''"]
  #   compiler.put_cmd    = "_erbout.<<"
  #   compiler.insert_cmd = "_erbout.<<"
  #   compiler.post_cmd   = ["_erbout"]
  #
  #   code, enc = compiler.compile("Got <%= obj %>!\n")
  #   puts code
  #
  # <i>Generates</i>:
  #
  #   #coding:UTF-8
  #   _erbout=+''; _erbout.<< "Got ".freeze; _erbout.<<(( obj ).to_s); _erbout.<< "!\n".freeze; _erbout
  #
  # By default the output is sent to the print method.  For example:
  #
  #   compiler = ERB::Compiler.new('<>')
  #   code, enc = compiler.compile("Got <%= obj %>!\n")
  #   puts code
  #
  # <i>Generates</i>:
  #
  #   #coding:UTF-8
  #   print "Got ".freeze; print(( obj ).to_s); print "!\n".freeze
  #
  # == Evaluation
  #
  # The compiled code can be used in any context where the names in the code
  # correctly resolve. Using the last example, each of these print 'Got It!'
  #
  # Evaluate using a variable:
  #
  #   obj = 'It'
  #   eval code
  #
  # Evaluate using an input:
  #
  #   mod = Module.new
  #   mod.module_eval %{
  #     def get(obj)
  #       #{code}
  #     end
  #   }
  #   extend mod
  #   get('It')
  #
  # Evaluate using an accessor:
  #
  #   klass = Class.new Object
  #   klass.class_eval %{
  #     attr_accessor :obj
  #     def initialize(obj)
  #       @obj = obj
  #     end
  #     def get_it
  #       #{code}
  #     end
  #   }
  #   klass.new('It').get_it
  #
  # Good! See also ERB#def_method, ERB#def_module, and ERB#def_class.
  class Compiler # :nodoc:
    class PercentLine # :nodoc:
      def initialize(str)
        @value = str
      end
      attr_reader :value
      alias :to_s :value
    end

    class Scanner # :nodoc:
      @scanner_map = {}
      class << self
        def register_scanner(klass, trim_mode, percent)
          @scanner_map[[trim_mode, percent]] = klass
        end
        alias :regist_scanner :register_scanner
      end

      def self.default_scanner=(klass)
        @default_scanner = klass
      end

      def self.make_scanner(src, trim_mode, percent)
        klass = @scanner_map.fetch([trim_mode, percent], @default_scanner)
        klass.new(src, trim_mode, percent)
      end

      DEFAULT_STAGS = %w(<%% <%= <%# <%).freeze
      DEFAULT_ETAGS = %w(%%> %>).freeze
      def initialize(src, trim_mode, percent)
        @src = src
        @stag = nil
        @stags = DEFAULT_STAGS
        @etags = DEFAULT_ETAGS
      end
      attr_accessor :stag
      attr_reader :stags, :etags

      def scan; end
    end

    class TrimScanner < Scanner # :nodoc:
      def initialize(src, trim_mode, percent)
        super
        @trim_mode = trim_mode
        @percent = percent
        if @trim_mode == '>'
          @scan_reg  = /(.*?)(%>\r?\n|#{(stags + etags).join('|')}|\n|\z)/m
          @scan_line = self.method(:trim_line1)
        elsif @trim_mode == '<>'
          @scan_reg  = /(.*?)(%>\r?\n|#{(stags + etags).join('|')}|\n|\z)/m
          @scan_line = self.method(:trim_line2)
        elsif @trim_mode == '-'
          @scan_reg  = /(.*?)(^[ \t]*<%\-|<%\-|-%>\r?\n|-%>|#{(stags + etags).join('|')}|\z)/m
          @scan_line = self.method(:explicit_trim_line)
        else
          @scan_reg  = /(.*?)(#{(stags + etags).join('|')}|\n|\z)/m
          @scan_line = self.method(:scan_line)
        end
      end

      def scan(&block)
        @stag = nil
        if @percent
          @src.each_line do |line|
            percent_line(line, &block)
          end
        else
          @scan_line.call(@src, &block)
        end
        nil
      end

      def percent_line(line, &block)
        if @stag || line[0] != ?%
          return @scan_line.call(line, &block)
        end

        line[0] = ''
        if line[0] == ?%
          @scan_line.call(line, &block)
        else
          yield(PercentLine.new(line.chomp))
        end
      end

      def scan_line(line)
        line.scan(@scan_reg) do |tokens|
          tokens.each do |token|
            next if token.empty?
            yield(token)
          end
        end
      end

      def trim_line1(line)
        line.scan(@scan_reg) do |tokens|
          tokens.each do |token|
            next if token.empty?
            if token == "%>\n" || token == "%>\r\n"
              yield('%>')
              yield(:cr)
            else
              yield(token)
            end
          end
        end
      end

      def trim_line2(line)
        head = nil
        line.scan(@scan_reg) do |tokens|
          tokens.each do |token|
            next if token.empty?
            head = token unless head
            if token == "%>\n" || token == "%>\r\n"
              yield('%>')
              if is_erb_stag?(head)
                yield(:cr)
              else
                yield("\n")
              end
              head = nil
            else
              yield(token)
              head = nil if token == "\n"
            end
          end
        end
      end

      def explicit_trim_line(line)
        line.scan(@scan_reg) do |tokens|
          tokens.each do |token|
            next if token.empty?
            if @stag.nil? && /[ \t]*<%-/ =~ token
              yield('<%')
            elsif @stag && (token == "-%>\n" || token == "-%>\r\n")
              yield('%>')
              yield(:cr)
            elsif @stag && token == '-%>'
              yield('%>')
            else
              yield(token)
            end
          end
        end
      end

      ERB_STAG = %w(<%= <%# <%)
      def is_erb_stag?(s)
        ERB_STAG.member?(s)
      end
    end

    Scanner.default_scanner = TrimScanner

    begin
      require 'strscan'
    rescue LoadError
    else
      class SimpleScanner < Scanner # :nodoc:
        def scan
          stag_reg = (stags == DEFAULT_STAGS) ? /(.*?)(<%[%=#]?|\z)/m : /(.*?)(#{stags.join('|')}|\z)/m
          etag_reg = (etags == DEFAULT_ETAGS) ? /(.*?)(%%?>|\z)/m : /(.*?)(#{etags.join('|')}|\z)/m
          scanner = StringScanner.new(@src)
          while ! scanner.eos?
            scanner.scan(@stag ? etag_reg : stag_reg)
            yield(scanner[1])
            yield(scanner[2])
          end
        end
      end
      Scanner.register_scanner(SimpleScanner, nil, false)

      class ExplicitScanner < Scanner # :nodoc:
        def scan
          stag_reg = /(.*?)(^[ \t]*<%-|<%-|#{stags.join('|')}|\z)/m
          etag_reg = /(.*?)(-%>|#{etags.join('|')}|\z)/m
          scanner = StringScanner.new(@src)
          while ! scanner.eos?
            scanner.scan(@stag ? etag_reg : stag_reg)
            yield(scanner[1])

            elem = scanner[2]
            if /[ \t]*<%-/ =~ elem
              yield('<%')
            elsif elem == '-%>'
              yield('%>')
              yield(:cr) if scanner.scan(/(\r?\n|\z)/)
            else
              yield(elem)
            end
          end
        end
      end
      Scanner.register_scanner(ExplicitScanner, '-', false)
    end

    class Buffer # :nodoc:
      def initialize(compiler, enc=nil, frozen=nil)
        @compiler = compiler
        @line = []
        @script = +''
        @script << "#coding:#{enc}\n" if enc
        @script << "#frozen-string-literal:#{frozen}\n" unless frozen.nil?
        @compiler.pre_cmd.each do |x|
          push(x)
        end
      end
      attr_reader :script

      def push(cmd)
        @line << cmd
      end

      def cr
        @script << (@line.join('; '))
        @line = []
        @script << "\n"
      end

      def close
        return unless @line
        @compiler.post_cmd.each do |x|
          push(x)
        end
        @script << (@line.join('; '))
        @line = nil
      end
    end

    def add_put_cmd(out, content)
      out.push("#{@put_cmd} #{content.dump}.freeze#{"\n" * content.count("\n")}")
    end

    def add_insert_cmd(out, content)
      out.push("#{@insert_cmd}((#{content}).to_s)")
    end

    # Compiles an ERB template into Ruby code.  Returns an array of the code
    # and encoding like ["code", Encoding].
    def compile(s)
      enc = s.encoding
      raise ArgumentError, "#{enc} is not ASCII compatible" if enc.dummy?
      s = s.b # see String#b
      magic_comment = detect_magic_comment(s, enc)
      out = Buffer.new(self, *magic_comment)

      self.content = +''
      scanner = make_scanner(s)
      scanner.scan do |token|
        next if token.nil?
        next if token == ''
        if scanner.stag.nil?
          compile_stag(token, out, scanner)
        else
          compile_etag(token, out, scanner)
        end
      end
      add_put_cmd(out, content) if content.size > 0
      out.close
      return out.script, *magic_comment
    end

    def compile_stag(stag, out, scanner)
      case stag
      when PercentLine
        add_put_cmd(out, content) if content.size > 0
        self.content = +''
        out.push(stag.to_s)
        out.cr
      when :cr
        out.cr
      when '<%', '<%=', '<%#'
        scanner.stag = stag
        add_put_cmd(out, content) if content.size > 0
        self.content = +''
      when "\n"
        content << "\n"
        add_put_cmd(out, content)
        self.content = +''
      when '<%%'
        content << '<%'
      else
        content << stag
      end
    end

    def compile_etag(etag, out, scanner)
      case etag
      when '%>'
        compile_content(scanner.stag, out)
        scanner.stag = nil
        self.content = +''
      when '%%>'
        content << '%>'
      else
        content << etag
      end
    end

    def compile_content(stag, out)
      case stag
      when '<%'
        if content[-1] == ?\n
          content.chop!
          out.push(content)
          out.cr
        else
          out.push(content)
        end
      when '<%='
        add_insert_cmd(out, content)
      when '<%#'
        # commented out
      end
    end

    def prepare_trim_mode(mode) # :nodoc:
      case mode
      when 1
        return [false, '>']
      when 2
        return [false, '<>']
      when 0, nil
        return [false, nil]
      when String
        unless mode.match?(/\A(%|-|>|<>){1,2}\z/)
          warn_invalid_trim_mode(mode, uplevel: 5)
        end

        perc = mode.include?('%')
        if mode.include?('-')
          return [perc, '-']
        elsif mode.include?('<>')
          return [perc, '<>']
        elsif mode.include?('>')
          return [perc, '>']
        else
          [perc, nil]
        end
      else
        warn_invalid_trim_mode(mode, uplevel: 5)
        return [false, nil]
      end
    end

    def make_scanner(src) # :nodoc:
      Scanner.make_scanner(src, @trim_mode, @percent)
    end

    # Construct a new compiler using the trim_mode. See ERB::new for available
    # trim modes.
    def initialize(trim_mode)
      @percent, @trim_mode = prepare_trim_mode(trim_mode)
      @put_cmd = 'print'
      @insert_cmd = @put_cmd
      @pre_cmd = []
      @post_cmd = []
    end
    attr_reader :percent, :trim_mode

    # The command to handle text that ends with a newline
    attr_accessor :put_cmd

    # The command to handle text that is inserted prior to a newline
    attr_accessor :insert_cmd

    # An array of commands prepended to compiled code
    attr_accessor :pre_cmd

    # An array of commands appended to compiled code
    attr_accessor :post_cmd

    private

    # A buffered text in #compile
    attr_accessor :content

    def detect_magic_comment(s, enc = nil)
      re = @percent ? /\G(?:<%#(.*)%>|%#(.*)\n)/ : /\G<%#(.*)%>/
      frozen = nil
      s.scan(re) do
        comment = $+
        comment = $1 if comment[/-\*-\s*([^\s].*?)\s*-\*-$/]
        case comment
        when %r"coding\s*[=:]\s*([[:alnum:]\-_]+)"
          enc = Encoding.find($1.sub(/-(?:mac|dos|unix)/i, ''))
        when %r"frozen[-_]string[-_]literal\s*:\s*([[:alnum:]]+)"
          frozen = $1
        end
      end
      return enc, frozen
    end

    def warn_invalid_trim_mode(mode, uplevel:)
      warn "Invalid ERB trim mode: #{mode.inspect} (trim_mode: nil, 0, 1, 2, or String composed of '%' and/or '-', '>', '<>')", uplevel: uplevel + 1
    end
  end
end

#--
# ERB
class ERB
  #
  # Constructs a new ERB object with the template specified in _str_.
  #
  # An ERB object works by building a chunk of Ruby code that will output
  # the completed template when run.
  #
  # If _trim_mode_ is passed a String containing one or more of the following
  # modifiers, ERB will adjust its code generation as listed:
  #
  #     %  enables Ruby code processing for lines beginning with %
  #     <> omit newline for lines starting with <% and ending in %>
  #     >  omit newline for lines ending in %>
  #     -  omit blank lines ending in -%>
  #
  # _eoutvar_ can be used to set the name of the variable ERB will build up
  # its output in.  This is useful when you need to run multiple ERB
  # templates through the same binding and/or when you want to control where
  # output ends up.  Pass the name of the variable to be used inside a String.
  #
  # === Example
  #
  #  require "erb"
  #
  #  # build data class
  #  class Listings
  #    PRODUCT = { :name => "Chicken Fried Steak",
  #                :desc => "A well messages pattie, breaded and fried.",
  #                :cost => 9.95 }
  #
  #    attr_reader :product, :price
  #
  #    def initialize( product = "", price = "" )
  #      @product = product
  #      @price = price
  #    end
  #
  #    def build
  #      b = binding
  #      # create and run templates, filling member data variables
  #      ERB.new(<<-'END_PRODUCT'.gsub(/^\s+/, ""), trim_mode: "", eoutvar: "@product").result b
  #        <%= PRODUCT[:name] %>
  #        <%= PRODUCT[:desc] %>
  #      END_PRODUCT
  #      ERB.new(<<-'END_PRICE'.gsub(/^\s+/, ""), trim_mode: "", eoutvar: "@price").result b
  #        <%= PRODUCT[:name] %> -- <%= PRODUCT[:cost] %>
  #        <%= PRODUCT[:desc] %>
  #      END_PRICE
  #    end
  #  end
  #
  #  # setup template data
  #  listings = Listings.new
  #  listings.build
  #
  #  puts listings.product + "\n" + listings.price
  #
  # _Generates_
  #
  #  Chicken Fried Steak
  #  A well messages pattie, breaded and fried.
  #
  #  Chicken Fried Steak -- 9.95
  #  A well messages pattie, breaded and fried.
  #
  def initialize(str, safe_level=NOT_GIVEN, legacy_trim_mode=NOT_GIVEN, legacy_eoutvar=NOT_GIVEN, trim_mode: nil, eoutvar: '_erbout')
    # Complex initializer for $SAFE deprecation at [Feature #14256]. Use keyword arguments to pass trim_mode or eoutvar.
    if safe_level != NOT_GIVEN
      warn 'Passing safe_level with the 2nd argument of ERB.new is deprecated. Do not use it, and specify other arguments as keyword arguments.', uplevel: 1
    end
    if legacy_trim_mode != NOT_GIVEN
      warn 'Passing trim_mode with the 3rd argument of ERB.new is deprecated. Use keyword argument like ERB.new(str, trim_mode: ...) instead.', uplevel: 1
      trim_mode = legacy_trim_mode
    end
    if legacy_eoutvar != NOT_GIVEN
      warn 'Passing eoutvar with the 4th argument of ERB.new is deprecated. Use keyword argument like ERB.new(str, eoutvar: ...) instead.', uplevel: 1
      eoutvar = legacy_eoutvar
    end

    compiler = make_compiler(trim_mode)
    set_eoutvar(compiler, eoutvar)
    @src, @encoding, @frozen_string = *compiler.compile(str)
    @filename = nil
    @lineno = 0
    @_init = self.class.singleton_class
  end
  NOT_GIVEN = Object.new
  private_constant :NOT_GIVEN

  ##
  # Creates a new compiler for ERB.  See ERB::Compiler.new for details

  def make_compiler(trim_mode)
    ERB::Compiler.new(trim_mode)
  end

  # The Ruby code generated by ERB
  attr_reader :src

  # The encoding to eval
  attr_reader :encoding

  # The optional _filename_ argument passed to Kernel#eval when the ERB code
  # is run
  attr_accessor :filename

  # The optional _lineno_ argument passed to Kernel#eval when the ERB code
  # is run
  attr_accessor :lineno

  #
  # Sets optional filename and line number that will be used in ERB code
  # evaluation and error reporting. See also #filename= and #lineno=
  #
  #   erb = ERB.new('<%= some_x %>')
  #   erb.render
  #   # undefined local variable or method `some_x'
  #   #   from (erb):1
  #
  #   erb.location = ['file.erb', 3]
  #   # All subsequent error reporting would use new location
  #   erb.render
  #   # undefined local variable or method `some_x'
  #   #   from file.erb:4
  #
  def location=((filename, lineno))
    @filename = filename
    @lineno = lineno if lineno
  end

  #
  # Can be used to set _eoutvar_ as described in ERB::new.  It's probably
  # easier to just use the constructor though, since calling this method
  # requires the setup of an ERB _compiler_ object.
  #
  def set_eoutvar(compiler, eoutvar = '_erbout')
    compiler.put_cmd = "#{eoutvar}.<<"
    compiler.insert_cmd = "#{eoutvar}.<<"
    compiler.pre_cmd = ["#{eoutvar} = +''"]
    compiler.post_cmd = [eoutvar]
  end

  # Generate results and print them. (see ERB#result)
  def run(b=new_toplevel)
    print self.result(b)
  end

  #
  # Executes the generated ERB code to produce a completed template, returning
  # the results of that code.  (See ERB::new for details on how this process
  # can be affected by _safe_level_.)
  #
  # _b_ accepts a Binding object which is used to set the context of
  # code evaluation.
  #
  def result(b=new_toplevel)
    unless @_init.equal?(self.class.singleton_class)
      raise ArgumentError, "not initialized"
    end
    eval(@src, b, (@filename || '(erb)'), @lineno)
  end

  # Render a template on a new toplevel binding with local variables specified
  # by a Hash object.
  def result_with_hash(hash)
    b = new_toplevel(hash.keys)
    hash.each_pair do |key, value|
      b.local_variable_set(key, value)
    end
    result(b)
  end

  ##
  # Returns a new binding each time *near* TOPLEVEL_BINDING for runs that do
  # not specify a binding.

  def new_toplevel(vars = nil)
    b = TOPLEVEL_BINDING
    if vars
      vars = vars.select {|v| b.local_variable_defined?(v)}
      unless vars.empty?
        return b.eval("tap {|;#{vars.join(',')}| break binding}")
      end
    end
    b.dup
  end
  private :new_toplevel

  # Define _methodname_ as instance method of _mod_ from compiled Ruby source.
  #
  # example:
  #   filename = 'example.rhtml'   # 'arg1' and 'arg2' are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.def_method(MyClass, 'render(arg1, arg2)', filename)
  #   print MyClass.new.render('foo', 123)
  def def_method(mod, methodname, fname='(ERB)')
    src = self.src.sub(/^(?!#|$)/) {"def #{methodname}\n"} << "\nend\n"
    mod.module_eval do
      eval(src, binding, fname, -1)
    end
  end

  # Create unnamed module, define _methodname_ as instance method of it, and return it.
  #
  # example:
  #   filename = 'example.rhtml'   # 'arg1' and 'arg2' are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.filename = filename
  #   MyModule = erb.def_module('render(arg1, arg2)')
  #   class MyClass
  #     include MyModule
  #   end
  def def_module(methodname='erb')
    mod = Module.new
    def_method(mod, methodname, @filename || '(ERB)')
    mod
  end

  # Define unnamed class which has _methodname_ as instance method, and return it.
  #
  # example:
  #   class MyClass_
  #     def initialize(arg1, arg2)
  #       @arg1 = arg1;  @arg2 = arg2
  #     end
  #   end
  #   filename = 'example.rhtml'  # @arg1 and @arg2 are used in example.rhtml
  #   erb = ERB.new(File.read(filename))
  #   erb.filename = filename
  #   MyClass = erb.def_class(MyClass_, 'render()')
  #   print MyClass.new('foo', 123).render()
  def def_class(superklass=Object, methodname='result')
    cls = Class.new(superklass)
    def_method(cls, methodname, @filename || '(ERB)')
    cls
  end
end

#--
# ERB::Util
class ERB
  # A utility module for conversion routines, often handy in HTML generation.
  module Util
    public
    #
    # A utility method for escaping HTML tag characters in _s_.
    #
    #   require "erb"
    #   include ERB::Util
    #
    #   puts html_escape("is a > 0 & a < 10?")
    #
    # _Generates_
    #
    #   is a &gt; 0 &amp; a &lt; 10?
    #
    def html_escape(s)
      CGI.escapeHTML(s.to_s)
    end
    alias h html_escape
    module_function :h
    module_function :html_escape

    #
    # A utility method for encoding the String _s_ as a URL.
    #
    #   require "erb"
    #   include ERB::Util
    #
    #   puts url_encode("Programming Ruby:  The Pragmatic Programmer's Guide")
    #
    # _Generates_
    #
    #   Programming%20Ruby%3A%20%20The%20Pragmatic%20Programmer%27s%20Guide
    #
    def url_encode(s)
      s.to_s.b.gsub(/[^a-zA-Z0-9_\-.~]/n) { |m|
        sprintf("%%%02X", m.unpack1("C"))
      }
    end
    alias u url_encode
    module_function :u
    module_function :url_encode
  end
end

#--
# ERB::DefMethod
class ERB
  # Utility module to define eRuby script as instance method.
  #
  # === Example
  #
  # example.rhtml:
  #   <% for item in @items %>
  #   <b><%= item %></b>
  #   <% end %>
  #
  # example.rb:
  #   require 'erb'
  #   class MyClass
  #     extend ERB::DefMethod
  #     def_erb_method('render()', 'example.rhtml')
  #     def initialize(items)
  #       @items = items
  #     end
  #   end
  #   print MyClass.new([10,20,30]).render()
  #
  # result:
  #
  #   <b>10</b>
  #
  #   <b>20</b>
  #
  #   <b>30</b>
  #
  module DefMethod
    public
    # define _methodname_ as instance method of current module, using ERB
    # object or eRuby file
    def def_erb_method(methodname, erb_or_fname)
      if erb_or_fname.kind_of? String
        fname = erb_or_fname
        erb = ERB.new(File.read(fname))
        erb.def_method(self, methodname, fname)
      else
        erb = erb_or_fname
        erb.def_method(self, methodname, erb.filename || '(ERB)')
      end
    end
    module_function :def_erb_method
  end
end
