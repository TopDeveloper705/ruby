begin
  require_relative "lib/net/http/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "net-http"
  spec.version       = Net::Http::VERSION
  spec.authors       = ["NARUSE, Yui"]
  spec.email         = ["naruse@airemix.jp"]

  spec.summary       = %q{HTTP client api for Ruby.}
  spec.description   = %q{HTTP client api for Ruby.}
  spec.homepage      = "https://github.com/ruby/net-http"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
