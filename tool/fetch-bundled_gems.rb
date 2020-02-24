#!ruby -an
BEGIN {
  require 'fileutils'

  dir = ARGV.shift
  ARGF.eof?
  FileUtils.mkdir_p(dir)
  Dir.chdir(dir)
}

n, v, u = $F

if File.directory?(n)
  puts "updating #{n} ..."
  system("git", (v == "master" ? "pull" : "fetch"), chdir: n) or abort
else
  puts "retrieving #{n} ..."
  system(*%W"git clone #{u} #{n}") or abort
end
unless system(*%W"git checkout #{v.sub(/\A(?=\d)/, 'v')}", chdir: n)
  unless /\A\d/ =~ v and system(*%W"git checkout #{v}", chdir: n)
    abort
  end
end
