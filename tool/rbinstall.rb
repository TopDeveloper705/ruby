#!./miniruby

# Used by the "make install" target to install Ruby.
# See common.mk for more details.

ENV["SDKROOT"] ||= "" if /darwin/ =~ RUBY_PLATFORM

begin
  load "./rbconfig.rb"
rescue LoadError
  CONFIG = Hash.new {""}
else
  include RbConfig
  $".unshift File.expand_path("./rbconfig.rb")
end

srcdir = File.expand_path('../..', __FILE__)
unless defined?(CROSS_COMPILING) and CROSS_COMPILING
  $:.replace([srcdir+"/lib", Dir.pwd])
end
require 'fileutils'
require 'shellwords'
require 'optparse'
require 'optparse/shellwords'
require 'rubygems'
begin
  require "zlib"
rescue LoadError
  $" << "zlib.rb"
end

INDENT = " "*36
STDOUT.sync = true
File.umask(022)

def parse_args(argv = ARGV)
  $mantype = 'doc'
  $destdir = nil
  $extout = nil
  $make = 'make'
  $mflags = []
  $install = []
  $installed = {}
  $installed_list = nil
  $exclude = []
  $dryrun = false
  $rdocdir = nil
  $htmldir = nil
  $data_mode = 0644
  $prog_mode = 0755
  $dir_mode = nil
  $script_mode = nil
  $strip = false
  $debug_symbols = nil
  $cmdtype = (if File::ALT_SEPARATOR == '\\'
                File.exist?("rubystub.exe") ? 'exe' : 'cmd'
              end)
  mflags = []
  gnumake = false
  opt = OptionParser.new
  opt.on('-n', '--dry-run') {$dryrun = true}
  opt.on('--dest-dir=DIR') {|dir| $destdir = dir}
  opt.on('--extout=DIR') {|dir| $extout = (dir unless dir.empty?)}
  opt.on('--ext-build-dir=DIR') {|v| $ext_build_dir = v }
  opt.on('--make=COMMAND') {|make| $make = make}
  opt.on('--mantype=MAN') {|man| $mantype = man}
  opt.on('--make-flags=FLAGS', '--mflags', Shellwords) do |v|
    if arg = v.first
      arg.insert(0, '-') if /\A[^-][^=]*\Z/ =~ arg
    end
    $mflags.concat(v)
  end
  opt.on('-i', '--install=TYPE', $install_procs.keys) do |ins|
    $install << ins
  end
  opt.on('-x', '--exclude=TYPE', $install_procs.keys) do |exc|
    $exclude << exc
  end
  opt.on('--data-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $data_mode = mode
  end
  opt.on('--prog-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $prog_mode = mode
  end
  opt.on('--dir-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $dir_mode = mode
  end
  opt.on('--script-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $script_mode = mode
  end
  opt.on('--installed-list [FILENAME]') {|name| $installed_list = name}
  opt.on('--rdoc-output [DIR]') {|dir| $rdocdir = dir}
  opt.on('--html-output [DIR]') {|dir| $htmldir = dir}
  opt.on('--cmd-type=TYPE', %w[cmd plain]) {|cmd| $cmdtype = (cmd unless cmd == 'plain')}
  opt.on('--[no-]strip') {|strip| $strip = strip}
  opt.on('--gnumake') {gnumake = true}
  opt.on('--debug-symbols=SUFFIX', /\w+/) {|name| $debug_symbols = ".#{name}"}

  opt.order!(argv) do |v|
    case v
    when /\AINSTALL[-_]([-\w]+)=(.*)/
      argv.unshift("--#{$1.tr('_', '-')}=#{$2}")
    when /\A\w[-\w]*=/
      mflags << v
    when /\A\w[-\w+]*\z/
      $install << v.intern
    else
      raise OptionParser::InvalidArgument, v
    end
  end rescue abort "#{$!.message}\n#{opt.help}"

  unless defined?(RbConfig)
    puts opt.help
    exit
  end

  $make, *rest = Shellwords.shellwords($make)
  $mflags.unshift(*rest) unless rest.empty?
  $mflags.unshift(*mflags)
  $mflags.reject! {|v| /\A-[OW]/ =~ v} if gnumake

  def $mflags.set?(flag)
    grep(/\A-(?!-).*#{flag.chr}/i) { return true }
    false
  end
  def $mflags.defined?(var)
    grep(/\A#{var}=(.*)/) {return block_given? ? yield($1) : $1}
    false
  end

  if $mflags.set?(?n)
    $dryrun = true
  else
    $mflags << '-n' if $dryrun
  end

  $destdir ||= $mflags.defined?("DESTDIR")
  if $extout ||= $mflags.defined?("EXTOUT")
    RbConfig.expand($extout)
  end

  $continue = $mflags.set?(?k)

  if $installed_list ||= $mflags.defined?('INSTALLED_LIST')
    RbConfig.expand($installed_list, RbConfig::CONFIG)
    $installed_list = open($installed_list, "ab")
    $installed_list.sync = true
  end

  $rdocdir ||= $mflags.defined?('RDOCOUT')
  $htmldir ||= $mflags.defined?('HTMLOUT')

  $dir_mode ||= $prog_mode | 0700
  $script_mode ||= $prog_mode
  if $ext_build_dir.nil?
    raise OptionParser::MissingArgument.new("--ext-build-dir=DIR")
  end
end

$install_procs = Hash.new {[]}
def install?(*types, &block)
  unless types.delete(:nodefault)
    $install_procs[:all] <<= block
  end
  types.each do |type|
    $install_procs[type] <<= block
  end
end

def strip_file(files)
  if !defined?($strip_command) and (cmd = CONFIG["STRIP"])
    case cmd
    when "", "true", ":" then return
    else $strip_command = Shellwords.shellwords(cmd)
    end
  elsif !$strip_command
    return
  end
  system(*($strip_command + [files].flatten))
end

def install(src, dest, options = {})
  options = options.clone
  strip = options.delete(:strip)
  options[:preserve] = true
  srcs = Array(src).select {|s| !$installed[$made_dirs[dest] ? File.join(dest, s) : dest]}
  return if srcs.empty?
  src = srcs if Array === src
  d = with_destdir(dest)
  super(src, d, **options)
  srcs.each {|s| $installed[$made_dirs[dest] ? File.join(dest, s) : dest] = true}
  if strip
    d = srcs.map {|s| File.join(d, File.basename(s))} if $made_dirs[dest]
    strip_file(d)
  end
  if $installed_list
    dest = srcs.map {|s| File.join(dest, File.basename(s))} if $made_dirs[dest]
    $installed_list.puts dest
  end
end

def ln_sf(src, dest)
  super(src, with_destdir(dest))
  $installed_list.puts dest if $installed_list
end

$made_dirs = {}
def makedirs(dirs)
  dirs = fu_list(dirs)
  dirs.collect! do |dir|
    realdir = with_destdir(dir)
    realdir unless $made_dirs.fetch(dir) do
      $made_dirs[dir] = true
      $installed_list.puts(File.join(dir, "")) if $installed_list
      File.directory?(realdir)
    end
  end.compact!
  super(dirs, :mode => $dir_mode) unless dirs.empty?
end

FalseProc = proc {false}
def path_matcher(pat)
  if pat and !pat.empty?
    proc {|f| pat.any? {|n| File.fnmatch?(n, f)}}
  else
    FalseProc
  end
end

def install_recursive(srcdir, dest, options = {})
  opts = options.clone
  noinst = opts.delete(:no_install)
  glob = opts.delete(:glob) || "*"
  maxdepth = opts.delete(:maxdepth)
  subpath = (srcdir.size+1)..-1
  prune = []
  skip = []
  if noinst
    if Array === noinst
      prune = noinst.grep(/#{File::SEPARATOR}/o).map!{|f| f.chomp(File::SEPARATOR)}
      skip = noinst.grep(/\A[^#{File::SEPARATOR}]*\z/o)
    else
      if noinst.index(File::SEPARATOR)
        prune = [noinst]
      else
        skip = [noinst]
      end
    end
  end
  skip |= %w"#*# *~ *.old *.bak *.orig *.rej *.diff *.patch *.core"
  prune = path_matcher(prune)
  skip = path_matcher(skip)
  File.directory?(srcdir) or return rescue return
  paths = [[srcdir, dest, 0]]
  found = []
  while file = paths.shift
    found << file
    file, d, dir = *file
    if dir
      depth = dir + 1
      next if maxdepth and maxdepth < depth
      files = []
      Dir.foreach(file) do |f|
        src = File.join(file, f)
        d = File.join(dest, dir = src[subpath])
        stat = File.lstat(src) rescue next
        if stat.directory?
          files << [src, d, depth] if maxdepth != depth and /\A\./ !~ f and !prune[dir]
        elsif stat.symlink?
          # skip
        else
          files << [src, d, false] if File.fnmatch?(glob, f, File::FNM_EXTGLOB) and !skip[f]
        end
      end
      paths.insert(0, *files)
    end
  end
  for src, d, dir in found
    if dir
      next
      # makedirs(d)
    else
      makedirs(d[/.*(?=\/)/m])
      if block_given?
        yield src, d, opts
      else
        install src, d, opts
      end
    end
  end
end

def open_for_install(path, mode)
  data = open(realpath = with_destdir(path), "rb") {|f| f.read} rescue nil
  newdata = yield
  unless $dryrun
    unless newdata == data
      open(realpath, "wb", mode) {|f| f.write newdata}
    end
    File.chmod(mode, realpath)
  end
  $installed_list.puts path if $installed_list
end

def with_destdir(dir)
  return dir if !$destdir or $destdir.empty?
  dir = dir.sub(/\A\w:/, '') if File::PATH_SEPARATOR == ';'
  $destdir + dir
end

def without_destdir(dir)
  return dir if !$destdir or $destdir.empty?
  dir.start_with?($destdir) ? dir[$destdir.size..-1] : dir
end

def prepare(mesg, basedir, subdirs=nil)
  return unless basedir
  case
  when !subdirs
    dirs = basedir
  when subdirs.size == 0
    subdirs = nil
  when subdirs.size == 1
    dirs = [basedir = File.join(basedir, subdirs)]
    subdirs = nil
  else
    dirs = [basedir, *subdirs.collect {|dir| File.join(basedir, dir)}]
  end
  printf("%-*s%s%s\n", INDENT.size, "installing #{mesg}:", basedir,
         (subdirs ? " (#{subdirs.join(', ')})" : ""))
  makedirs(dirs)
end

def CONFIG.[](name, mandatory = false)
  value = super(name)
  if mandatory
    raise "CONFIG['#{name}'] must be set" if !value or value.empty?
  end
  value
end

exeext = CONFIG["EXEEXT"]

ruby_install_name = CONFIG["ruby_install_name", true]
rubyw_install_name = CONFIG["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name

bindir = CONFIG["bindir", true]
libdir = CONFIG[CONFIG.fetch("libdirname", "libdir"), true]
rubyhdrdir = CONFIG["rubyhdrdir", true]
archhdrdir = CONFIG["rubyarchhdrdir"] || (rubyhdrdir + "/" + CONFIG['arch'])
rubylibdir = CONFIG["rubylibdir", true]
archlibdir = CONFIG["rubyarchdir", true]
if CONFIG["sitedir"]
  sitelibdir = CONFIG["sitelibdir"]
  sitearchlibdir = CONFIG["sitearchdir"]
end
if CONFIG["vendordir"]
  vendorlibdir = CONFIG["vendorlibdir"]
  vendorarchlibdir = CONFIG["vendorarchdir"]
end
mandir = CONFIG["mandir", true]
docdir = CONFIG["docdir", true]
enable_shared = CONFIG["ENABLE_SHARED"] == 'yes'
dll = CONFIG["LIBRUBY_SO", enable_shared]
lib = CONFIG["LIBRUBY", true]
arc = CONFIG["LIBRUBY_A", true]
load_relative = CONFIG["LIBRUBY_RELATIVE"] == 'yes'

rdoc_noinst = %w[created.rid]

install?(:local, :arch, :bin, :'bin-arch') do
  prepare "binary commands", bindir

  install ruby_install_name+exeext, bindir, :mode => $prog_mode, :strip => $strip
  if rubyw_install_name and !rubyw_install_name.empty?
    install rubyw_install_name+exeext, bindir, :mode => $prog_mode, :strip => $strip
  end
  # emcc produces ruby and ruby.wasm, the first is a JavaScript file of runtime support
  # to load and execute the second .wasm file. Both are required to execute ruby
  if RUBY_PLATFORM =~ /emscripten/ and File.exist? ruby_install_name+".wasm"
    install ruby_install_name+".wasm", bindir, :mode => $prog_mode, :strip => $strip
  end
  if File.exist? goruby_install_name+exeext
    install goruby_install_name+exeext, bindir, :mode => $prog_mode, :strip => $strip
  end
  if enable_shared and dll != lib
    install dll, bindir, :mode => $prog_mode, :strip => $strip
  end
end

install?(:local, :arch, :lib, :'lib-arch') do
  prepare "base libraries", libdir

  install lib, libdir, :mode => $prog_mode, :strip => $strip unless lib == arc
  install arc, libdir, :mode => $data_mode unless CONFIG["INSTALL_STATIC_LIBRARY"] == "no"
  if dll == lib and dll != arc
    for link in CONFIG["LIBRUBY_ALIASES"].split - [File.basename(dll)]
      ln_sf(dll, File.join(libdir, link))
    end
  end

  prepare "arch files", archlibdir
  install "rbconfig.rb", archlibdir, :mode => $data_mode
  if CONFIG["ARCHFILE"]
    for file in CONFIG["ARCHFILE"].split
      install file, archlibdir, :mode => $data_mode
    end
  end
end

install?(:local, :arch, :data) do
  pc = CONFIG["ruby_pc"]
  if pc and File.file?(pc) and File.size?(pc)
    prepare "pkgconfig data", pkgconfigdir = File.join(libdir, "pkgconfig")
    install pc, pkgconfigdir, :mode => $data_mode
  end
end

install?(:ext, :arch, :'ext-arch') do
  prepare "extension objects", archlibdir
  noinst = %w[-* -*/] | (CONFIG["no_install_files"] || "").split
  install_recursive("#{$extout}/#{CONFIG['arch']}", archlibdir, :no_install => noinst, :mode => $prog_mode, :strip => $strip)
  prepare "extension objects", sitearchlibdir
  prepare "extension objects", vendorarchlibdir
  if extso = File.read("exts.mk")[/^EXTSO[ \t]*=[ \t]*((?:.*\\\n)*.*)/, 1] and
    !(extso = extso.gsub(/\\\n/, '').split).empty?
    libpathenv = CONFIG["LIBPATHENV"]
    dest = CONFIG[!libpathenv || libpathenv == "PATH" ? "bindir" : "libdir"]
    prepare "external libraries", dest
    for file in extso
      install file, dest, :mode => $prog_mode
    end
  end
end
install?(:ext, :arch, :hdr, :'arch-hdr', :'hdr-arch') do
  prepare "extension headers", archhdrdir
  install_recursive("#{$extout}/include/#{CONFIG['arch']}", archhdrdir, :glob => "*.h", :mode => $data_mode)
  install_recursive("#{$extout}/include/#{CONFIG['arch']}", archhdrdir, :glob => "rb_mjit_header-*.obj", :mode => $data_mode)
  install_recursive("#{$extout}/include/#{CONFIG['arch']}", archhdrdir, :glob => "rb_mjit_header-*.pch", :mode => $data_mode)
end
install?(:ext, :comm, :'ext-comm') do
  prepare "extension scripts", rubylibdir
  install_recursive("#{$extout}/common", rubylibdir, :mode => $data_mode)
  prepare "extension scripts", sitelibdir
  prepare "extension scripts", vendorlibdir
end
install?(:ext, :comm, :hdr, :'comm-hdr', :'hdr-comm') do
  hdrdir = rubyhdrdir + "/ruby"
  prepare "extension headers", hdrdir
  install_recursive("#{$extout}/include/ruby", hdrdir, :glob => "*.h", :mode => $data_mode)
end

install?(:doc, :rdoc) do
  if $rdocdir
    ridatadir = File.join(CONFIG['ridir'], CONFIG['ruby_version'], "system")
    prepare "rdoc", ridatadir
    install_recursive($rdocdir, ridatadir, :no_install => rdoc_noinst, :mode => $data_mode)
  end
end
install?(:doc, :html) do
  if $htmldir
    prepare "html-docs", docdir
    install_recursive($htmldir, docdir+"/html", :no_install => rdoc_noinst, :mode => $data_mode)
  end
end
install?(:doc, :capi) do
  prepare "capi-docs", docdir
  install_recursive "doc/capi", docdir+"/capi", :mode => $data_mode
end

prolog_script = <<EOS
bindir="#{load_relative ? '${0%/*}' : bindir.gsub(/\"/, '\\\\"')}"
EOS
if CONFIG["LIBRUBY_RELATIVE"] != 'yes' and libpathenv = CONFIG["LIBPATHENV"]
  pathsep = File::PATH_SEPARATOR
  prolog_script << <<EOS
libdir="#{load_relative ? '$\{bindir%/bin\}/lib' : libdir.gsub(/\"/, '\\\\"')}"
export #{libpathenv}="$libdir${#{libpathenv}:+#{pathsep}$#{libpathenv}}"
EOS
end
prolog_script << %Q[exec "$bindir/#{ruby_install_name}" "-x" "$0" "$@"\n]
PROLOG_SCRIPT = {}
PROLOG_SCRIPT["exe"] = "#!#{bindir}/#{ruby_install_name}"
PROLOG_SCRIPT["cmd"] = <<EOS
:""||{ ""=> %q<-*- ruby -*-
@"%~dp0#{ruby_install_name}" -x "%~f0" %*
@exit /b %ERRORLEVEL%
};{ #\n#{prolog_script.gsub(/(?=\n)/, ' #')}>,\n}
EOS
PROLOG_SCRIPT.default = (load_relative || /\s/ =~ bindir) ?
                          <<EOS : PROLOG_SCRIPT["exe"]
#!/bin/sh
# -*- ruby -*-
_=_\\
=begin
#{prolog_script.chomp}
=end
EOS

installer = Struct.new(:ruby_shebang, :ruby_bin, :ruby_install_name, :stub, :trans) do
  def transform(name)
    RbConfig.expand(trans[name])
  end
end

$script_installer = Class.new(installer) do
  ruby_shebang = File.join(bindir, ruby_install_name)
  if File::ALT_SEPARATOR
    ruby_bin = ruby_shebang.tr(File::SEPARATOR, File::ALT_SEPARATOR)
  end
  if trans = CONFIG["program_transform_name"]
    exp = []
    trans.gsub!(/\$\$/, '$')
    trans.scan(%r[\G[\s;]*(/(?:\\.|[^/])*+/)?([sy])(\\?\W)((?:(?!\3)(?:\\.|.))*+)\3((?:(?!\3)(?:\\.|.))*+)\3([gi]*)]) do
      |addr, cmd, sep, pat, rep, opt|
      addr &&= Regexp.new(addr[/\A\/(.*)\/\z/, 1])
      case cmd
      when 's'
        next if pat == '^' and rep.empty?
        exp << [addr, (opt.include?('g') ? :gsub! : :sub!),
                Regexp.new(pat, opt.include?('i')), rep.gsub(/&/){'\&'}]
      when 'y'
        exp << [addr, :tr!, Regexp.quote(pat), rep]
      end
    end
    trans = proc do |base|
      exp.each {|addr, opt, pat, rep| base.__send__(opt, pat, rep) if !addr or addr =~ base}
      base
    end
  elsif /ruby/ =~ ruby_install_name
    trans = proc {|base| ruby_install_name.sub(/ruby/, base)}
  else
    trans = proc {|base| base}
  end

  def prolog(shebang)
    shebang.sub!(/\r$/, '')
    script = PROLOG_SCRIPT[$cmdtype]
    shebang.sub!(/\A(\#!.*?ruby\b)?/) do
      if script.end_with?("\n")
        script + ($1 || "#!ruby\n")
      else
        $1 ? script : "#{script}\n"
      end
    end
    shebang
  end

  def install(src, cmd)
    cmd = cmd.sub(/[^\/]*\z/m) {|n| transform(n)}

    shebang, body = open(src, "rb") do |f|
      next f.gets, f.read
    end
    shebang or raise "empty file - #{src}"
    shebang = prolog(shebang)
    body.gsub!(/\r$/, '')

    cmd << ".#{$cmdtype}" if $cmdtype
    open_for_install(cmd, $script_mode) do
      case $cmdtype
      when "exe"
        stub + shebang + body
      else
        shebang + body
      end
    end
  end

  def self.get_rubystub
    stubfile = "rubystub.exe"
    stub = File.open(stubfile, "rb") {|f| f.read} << "\n"
  rescue => e
    abort "No #{stubfile}: #{e}"
  else
    stub
  end

  def stub
    super or self.stub = self.class.get_rubystub
  end

  break new(ruby_shebang, ruby_bin, ruby_install_name, nil, trans)
end

install?(:local, :comm, :bin, :'bin-comm') do
  prepare "command scripts", bindir

  install_recursive(File.join(srcdir, "bin"), bindir, :maxdepth => 1) do |src, cmd|
    $script_installer.install(src, cmd)
  end
end

install?(:local, :comm, :lib) do
  prepare "library scripts", rubylibdir
  noinst = %w[*.txt *.rdoc *.gemspec]
  install_recursive(File.join(srcdir, "lib"), rubylibdir, :no_install => noinst, :mode => $data_mode)
end

install?(:local, :comm, :hdr, :'comm-hdr') do
  prepare "common headers", rubyhdrdir

  noinst = []
  unless RUBY_PLATFORM =~ /mswin|mingw|bccwin/
    noinst << "win32.h"
  end
  noinst = nil if noinst.empty?
  install_recursive(File.join(srcdir, "include"), rubyhdrdir, :no_install => noinst, :glob => "*.{h,hpp}", :mode => $data_mode)
end

install?(:local, :comm, :man) do
  mdocs = Dir["#{srcdir}/man/*.[1-9]"]
  prepare "manpages", mandir, ([] | mdocs.collect {|mdoc| mdoc[/\d+$/]}).sort.collect {|sec| "man#{sec}"}

  case $mantype
  when /\.(?:(gz)|bz2)\z/
    compress = $1 ? "gzip" : "bzip2"
    suffix = $&
  end
  mandir = File.join(mandir, "man")
  has_goruby = File.exist?(goruby_install_name+exeext)
  require File.join(srcdir, "tool/mdoc2man.rb") if /\Adoc\b/ !~ $mantype
  mdocs.each do |mdoc|
    next unless File.file?(mdoc) and open(mdoc){|fh| fh.read(1) == '.'}
    base = File.basename(mdoc)
    if base == "goruby.1"
      next unless has_goruby
    end

    destdir = mandir + (section = mdoc[/\d+$/])
    destname = ruby_install_name.sub(/ruby/, base.chomp(".#{section}"))
    destfile = File.join(destdir, "#{destname}.#{section}")

    if /\Adoc\b/ =~ $mantype
      if compress
        w = open(mdoc) {|f|
          stdin = STDIN.dup
          STDIN.reopen(f)
          begin
            destfile << suffix
            IO.popen(compress, &:read)
          ensure
            STDIN.reopen(stdin)
            stdin.close
          end
        }
        open_for_install(destfile, $data_mode) {w}
      else
        install mdoc, destfile, :mode => $data_mode
      end
    else
      class << (w = [])
        alias print push
      end
      if File.basename(mdoc).start_with?('bundle') ||
         File.basename(mdoc).start_with?('gemfile')
        w = File.read(mdoc)
      else
        open(mdoc) {|r| Mdoc2Man.mdoc2man(r, w)}
        w = w.join("")
      end
      if compress
        require 'tmpdir'
        Dir.mktmpdir("man") {|d|
          dest = File.join(d, File.basename(destfile))
          File.open(dest, "wb") {|f| f.write w}
          if system(compress, dest)
            w = File.open(dest+suffix, "rb") {|f| f.read}
            destfile << suffix
          end
        }
      end
      open_for_install(destfile, $data_mode) {w}
    end
  end
end

install?(:dbg, :nodefault) do
  prepare "debugger commands", bindir
  prepare "debugger scripts", rubylibdir
  conf = RbConfig::MAKEFILE_CONFIG.merge({"prefix"=>"${prefix#/}"})
  Dir.glob(File.join(srcdir, "template/ruby-*db.in")) do |src|
    cmd = $script_installer.transform(File.basename(src, ".in"))
    open_for_install(File.join(bindir, cmd), $script_mode) {
      RbConfig.expand(File.read(src), conf)
    }
  end
  install File.join(srcdir, "misc/lldb_cruby.py"), File.join(rubylibdir, "lldb_cruby.py")
  install File.join(srcdir, ".gdbinit"), File.join(rubylibdir, "gdbinit")
  if $debug_symbols
    {
      ruby_install_name => bindir,
      rubyw_install_name => bindir,
      goruby_install_name => bindir,
      dll => libdir,
    }.each do |src, dest|
      next if src.empty?
      src += $debug_symbols
      if File.directory?(src)
        install_recursive src, File.join(dest, src)
      end
    end
  end
end

module RbInstall
  def self.no_write(options = nil)
    u = File.umask(0022)
    if $dryrun
      fu = ::Object.class_eval do
        fu = remove_const(:FileUtils)
        const_set(:FileUtils, fu::NoWrite)
        fu
      end
      dir_mode = options.delete(:dir_mode) if options
    end
    yield
  ensure
    options[:dir_mode] = dir_mode if dir_mode
    if fu
      ::Object.class_eval do
        remove_const(:FileUtils)
        const_set(:FileUtils, fu)
      end
    end
    File.umask(u)
  end

  module Specs
    class FileCollector
      def initialize(gemspec)
        @gemspec = gemspec
        @base_dir = File.dirname(gemspec)
      end

      def collect
        (ruby_libraries + built_libraries).sort
      end

      def skip_install?(files)
        case type
        when "ext"
          # install ext only when it's configured
          !File.exist?("#{$ext_build_dir}/#{relative_base}/Makefile")
        when "lib"
          files.empty?
        end
      end

      private
      def type
        /\/(ext|lib)?\/.*?\z/ =~ @base_dir
        $1
      end

      def ruby_libraries
        case type
        when "ext"
          prefix = "#{$extout}/common/"
          base = "#{prefix}#{relative_base}"
        when "lib"
          base = @base_dir
          prefix = base.sub(/lib\/.*?\z/, "")
          # for lib/net/net-smtp.gemspec
          if m = File.basename(@gemspec, ".gemspec").match(/.*\-(.*)\z/)
            base = "#{@base_dir}/#{m[1]}" unless remove_prefix(prefix, @base_dir).include?(m[1])
          end
        end

        files = if base
                  Dir.glob("#{base}{.rb,/**/*.rb}").collect do |ruby_source|
                    remove_prefix(prefix, ruby_source)
                  end
                else
                  [File.basename(@gemspec, '.gemspec') + '.rb']
                end

        case File.basename(@gemspec, ".gemspec")
        when "net-http"
          files << "lib/net/https.rb"
        when "optparse"
          files << "lib/optionparser.rb"
        end

        files
      end

      def built_libraries
        case type
        when "ext"
          prefix = "#{$extout}/#{CONFIG['arch']}/"
          base = "#{prefix}#{relative_base}"
          dlext = CONFIG['DLEXT']
          Dir.glob("#{base}{.#{dlext},/**/*.#{dlext}}").collect do |built_library|
            remove_prefix(prefix, built_library)
          end
        when "lib"
          []
        else
          []
        end
      end

      def relative_base
        /\/#{Regexp.escape(type)}\/(.*?)\z/ =~ @base_dir
        $1
      end

      def remove_prefix(prefix, string)
        string.sub(/\A#{Regexp.escape(prefix)}/, "")
      end
    end
  end

  class DirPackage
    attr_reader :spec

    attr_accessor :dir_mode
    attr_accessor :prog_mode
    attr_accessor :data_mode

    def initialize(spec, dir_map = nil)
      @spec = spec
      @src_dir = File.dirname(@spec.loaded_from)
      @dir_map = dir_map
    end

    def extract_files(destination_dir, pattern = "*")
      return if @src_dir == destination_dir
      File.chmod(0700, destination_dir) unless $dryrun
      mode = pattern == File.join(spec.bindir, '*') ? prog_mode : data_mode
      destdir = without_destdir(destination_dir)
      if @dir_map
        (dir_map = @dir_map.map {|k, v| Regexp.quote(k) unless k == v}).compact!
        dir_map = %r{\A(?:#{dir_map.join('|')})(?=/)}
      end
      spec.files.each do |f|
        next unless File.fnmatch(pattern, f)
        src = File.join(@src_dir, dir_map =~ f ? "#{@dir_map[$&]}#{$'}" : f)
        dest = File.join(destdir, f)
        makedirs(dest[/.*(?=\/)/m])
        install src, dest, :mode => mode
      end
      File.chmod(dir_mode, destination_dir) unless $dryrun
    end
  end

  class GemInstaller < Gem::Installer
  end

  class UnpackedInstaller < GemInstaller
    def write_cache_file
    end

    def shebang(bin_file_name)
      path = File.join(gem_dir, spec.bindir, bin_file_name)
      first_line = File.open(path, "rb") {|file| file.gets}
      $script_installer.prolog(first_line).chomp
    end

    def app_script_text(bin_file_name)
      # move shell script part after comments generated by RubyGems.
      super.sub(/\A
        (\#!\/bin\/sh\n\#.*-\*-\s*ruby\s*-\*-.*\n)
        ((?:.*\n)*?\#!.*ruby.*\n)
        \#\n
        ((?:\#.*\n)+)/x, '\1\3\2')
    end

    def check_executable_overwrite(filename)
      return if @wrappers and same_bin_script?(filename, @bin_dir)
      super
    end

    def generate_bin_script(filename, bindir)
      return if same_bin_script?(filename, bindir)
      super
    end

    def same_bin_script?(filename, bindir)
      path = File.join(bindir, formatted_program_filename(filename))
      begin
        return true if File.binread(path) == app_script_text(filename)
      rescue
      end
      false
    end

    def write_spec
      super unless $dryrun
      $installed_list.puts(without_destdir(spec_file)) if $installed_list
    end

    def write_default_spec
      super unless $dryrun
      $installed_list.puts(without_destdir(default_spec_file)) if $installed_list
    end
  end

  class GemInstaller
    def install
      spec.post_install_message = nil
      RbInstall.no_write(options) {super}
    end

    def generate_bin_script(filename, bindir)
      name = formatted_program_filename(filename)
      unless $dryrun
        super
        File.chmod($script_mode, File.join(bindir, name))
      end
      $installed_list.puts(File.join(without_destdir(bindir), name)) if $installed_list
    end

    def verify_gem_home # :nodoc:
    end

    def ensure_writable_dir(dir)
      $made_dirs.fetch(d = without_destdir(dir)) do
        $made_dirs[d] = true
        super unless $dryrun
        $installed_list.puts(d+"/") if $installed_list
      end
    end
  end
end

# :startdoc:

install?(:ext, :comm, :gem, :'default-gems', :'default-gems-comm') do
  install_default_gem('lib', srcdir, bindir)
end
install?(:ext, :arch, :gem, :'default-gems', :'default-gems-arch') do
  install_default_gem('ext', srcdir, bindir)
end

def load_gemspec(file, expanded = false)
  file = File.realpath(file)
  code = File.read(file, encoding: "utf-8:-")
  code.gsub!(/(?:`git[^\`]*`|%x\[git[^\]]*\])\.split\([^\)]*\)/m) do
    files = []
    if expanded
      base = File.dirname(file)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: base) do |n|
        case File.basename(n); when ".", ".."; next; end
        next if File.directory?(File.join(base, n))
        files << n.dump
      end
    end
    "[" + files.join(", ") + "]"
  end
  spec = eval(code, binding, file)
  unless Gem::Specification === spec
    raise TypeError, "[#{file}] isn't a Gem::Specification (#{spec.class} instead)."
  end
  spec.loaded_from = file
  spec.files.reject! {|n| n.end_with?(".gemspec") or n.start_with?(".git")}

  spec
end

def install_default_gem(dir, srcdir, bindir)
  gem_dir = Gem.default_dir
  install_dir = with_destdir(gem_dir)
  prepare "default gems from #{dir}", gem_dir
  RbInstall.no_write do
    makedirs(Gem.ensure_default_gem_subdirectories(install_dir, $dir_mode).map {|d| File.join(gem_dir, d)})
  end

  options = {
    :install_dir => with_destdir(gem_dir),
    :bin_dir => with_destdir(bindir),
    :ignore_dependencies => true,
    :dir_mode => $dir_mode,
    :data_mode => $data_mode,
    :prog_mode => $script_mode,
    :wrappers => true,
    :format_executable => true,
    :install_as_default => true,
  }
  default_spec_dir = Gem.default_specifications_dir

  gems = Dir.glob("#{srcdir}/#{dir}/**/*.gemspec").map {|src|
    spec = load_gemspec(src)
    file_collector = RbInstall::Specs::FileCollector.new(src)
    files = file_collector.collect
    if file_collector.skip_install?(files)
      next
    end
    spec.files = files
    spec
  }
  gems.compact.sort_by(&:name).each do |gemspec|
    old_gemspecs = Dir[File.join(with_destdir(default_spec_dir), "#{gemspec.name}-*.gemspec")]
    if old_gemspecs.size > 0
      old_gemspecs.each {|spec| rm spec }
    end

    full_name = "#{gemspec.name}-#{gemspec.version}"

    gemspec.loaded_from = File.join srcdir, gemspec.spec_name

    package = RbInstall::DirPackage.new gemspec, {gemspec.bindir => 'libexec'}
    ins = RbInstall::UnpackedInstaller.new(package, options)
    puts "#{INDENT}#{gemspec.name} #{gemspec.version}"
    ins.install
  end
end

install?(:ext, :comm, :gem, :'bundled-gems') do
  if CONFIG['CROSS_COMPILING'] == 'yes'
    # The following hacky steps set "$ruby = BASERUBY" in tool/fake.rb
    $hdrdir = ''
    $extmk = nil
    $ruby = nil  # ...
    ruby_path = $ruby + " -I#{Dir.pwd}" # $baseruby + " -I#{Dir.pwd}"
  else
    # ruby_path = File.expand_path(with_destdir(File.join(bindir, ruby_install_name)))
    ENV['RUBYLIB'] = nil
    ENV['RUBYOPT'] = nil
    ruby_path = File.expand_path(with_destdir(File.join(bindir, ruby_install_name))) + " --disable=gems -I#{with_destdir(archlibdir)}"
  end
  Gem.instance_variable_set(:@ruby, ruby_path) if Gem.ruby != ruby_path

  gem_dir = Gem.default_dir
  install_dir = with_destdir(gem_dir)
  prepare "bundled gems", gem_dir
  RbInstall.no_write do
    makedirs(Gem.ensure_gem_subdirectories(install_dir, $dir_mode).map {|d| File.join(gem_dir, d)})
  end

  installed_gems = {}
  options = {
    :install_dir => install_dir,
    :bin_dir => with_destdir(bindir),
    :domain => :local,
    :ignore_dependencies => true,
    :dir_mode => $dir_mode,
    :data_mode => $data_mode,
    :prog_mode => $script_mode,
    :wrappers => true,
    :format_executable => true,
  }
  gem_ext_dir = "#$extout/gems/#{CONFIG['arch']}"
  extensions_dir = with_destdir(Gem::StubSpecification.gemspec_stub("", gem_dir, gem_dir).extensions_dir)

  File.foreach("#{srcdir}/gems/bundled_gems") do |name|
    next if /^\s*(?:#|$)/ =~ name
    next unless /^(\S+)\s+(\S+).*/ =~ name
    gem_name = "#$1-#$2"
    path = "#{srcdir}/.bundle/gems/#{gem_name}/#{gem_name}.gemspec"
    if File.exist?(path)
      spec = load_gemspec(path)
    else
      path = "#{srcdir}/.bundle/gems/#{gem_name}/#$1.gemspec"
      next unless File.exist?(path)
      spec = load_gemspec(path, true)
    end
    next unless spec.platform == Gem::Platform::RUBY
    next unless spec.full_name == gem_name
    if !spec.extensions.empty? && CONFIG["EXTSTATIC"] == "static"
      puts "skip installation of #{spec.name} #{spec.version}; bundled gem with an extension library is not supported on --with-static-linked-ext"
      next
    end
    spec.extension_dir = "#{extensions_dir}/#{spec.full_name}"
    if File.directory?(ext = "#{gem_ext_dir}/#{spec.full_name}")
      spec.extensions[0] ||= "-"
    end
    package = RbInstall::DirPackage.new spec
    ins = RbInstall::UnpackedInstaller.new(package, options)
    puts "#{INDENT}#{spec.name} #{spec.version}"
    ins.install
    unless $dryrun
      File.chmod($data_mode, File.join(install_dir, "specifications", "#{spec.full_name}.gemspec"))
    end
    unless spec.extensions.empty?
      install_recursive(ext, spec.extension_dir)
    end
    installed_gems[spec.full_name] = true
  end
  installed_gems, gems = Dir.glob(srcdir+'/gems/*.gem').partition {|gem| installed_gems.key?(File.basename(gem, '.gem'))}
  unless installed_gems.empty?
    prepare "bundled gem cache", gem_dir+"/cache"
    install installed_gems, gem_dir+"/cache"
  end
  next if gems.empty?
  if defined?(Zlib)
    Gem.instance_variable_set(:@ruby, with_destdir(File.join(bindir, ruby_install_name)))
    silent = Gem::SilentUI.new
    gems.each do |gem|
      package = Gem::Package.new(gem)
      inst = RbInstall::GemInstaller.new(package, options)
      inst.spec.extension_dir = "#{extensions_dir}/#{inst.spec.full_name}"
      begin
        Gem::DefaultUserInteraction.use_ui(silent) {inst.install}
      rescue Gem::InstallError
        next
      end
      gemname = File.basename(gem)
      puts "#{INDENT}#{gemname}"
    end
    # fix directory permissions
    # TODO: Gem.install should accept :dir_mode option or something
    File.chmod($dir_mode, *Dir.glob(install_dir+"/**/"))
    # fix .gemspec permissions
    File.chmod($data_mode, *Dir.glob(install_dir+"/specifications/*.gemspec"))
  else
    puts "skip installing bundled gems because of lacking zlib"
  end
end

parse_args()

include FileUtils
include FileUtils::NoWrite if $dryrun
@fileutils_output = STDOUT
@fileutils_label = ''

$install << :all if $install.empty?
installs = $install.map do |inst|
  if !(procs = $install_procs[inst]) || procs.empty?
    next warn("unknown install target - #{inst}")
  end
  procs
end
installs.flatten!
installs -= $exclude.map {|exc| $install_procs[exc]}.flatten
installs.each do |block|
  dir = Dir.pwd
  begin
    block.call
  ensure
    Dir.chdir(dir)
  end
end

# vi:set sw=2:
