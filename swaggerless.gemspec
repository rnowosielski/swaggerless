# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'swaggerless/version'

Gem::Specification.new do |spec|
  spec.name          = "swaggerless"
  spec.version       = Swaggerless::VERSION
  spec.authors       = ["Rafal Nowosielski"]
  spec.email         = ["rafal@nowosielski.email"]

  spec.summary       = "The gem includes common tasks needed to deploy design first serverless to the AWS"
  spec.description   = "The gem includes common tasks needed to deploy design first Open API spec to AWS using Lambdas and API Gateway"
  spec.homepage      = "https://open.cimpress.io"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

  spec.add_runtime_dependency "aws-sdk", "~> 2.6"
  spec.add_runtime_dependency "rubyzip"

end
