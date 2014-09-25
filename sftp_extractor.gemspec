# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sftp_extractor/version'

Gem::Specification.new do |spec|
  spec.name          = "sftp_extractor"
  spec.version       = SftpExtractor::VERSION
  spec.authors       = ["Nuno Costa"]
  spec.email         = ["nuno.mmc@gmail.com"]
  spec.summary       = %q{Executable meant to run in a cronjob to extract files from a SFTP server}
  spec.description   = %q{}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "net-sftp"
end
