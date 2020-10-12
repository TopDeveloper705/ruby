Gem::Specification.new do |spec|
  spec.name          = "io-nonblock"
  spec.version       = "0.1.0"
  spec.authors       = ["Nobu Nakada"]
  spec.email         = ["nobu@ruby-lang.org"]

  spec.summary       = %q{Enables non-blocking mode with IO class}
  spec.description   = %q{Enables non-blocking mode with IO class}
  spec.homepage      = "https://github.com/ruby/io-nonblock"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    %x[git ls-files -z].split("\x0").reject do |f|
      f.match(%r{\A(?:test|spec|features)/|\A\.(?:git|travis)})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
