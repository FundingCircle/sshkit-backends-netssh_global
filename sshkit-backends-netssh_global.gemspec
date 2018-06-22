# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|

  gem.authors       = ["Theo Cushion", "Dennis Ideler"]
  gem.email         = ["engineering+sshkit-backends-netssh_global@fundingcircle.com"]
  gem.summary       = %q{SSHKit backend for globally sudoing commands}
  gem.description   = %q{A backend to be used in conjunction with Capistrano 3
and SSHKit to allow deployment on setups where users login as one identity and
then need to sudo to a different identity for each command.}
  gem.homepage      = "https://github.com/FundingCircle/sshkit-backends-netssh_global"
  gem.license       = "BSD-3-Clause"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- test/*`.split("\n")
  gem.name          = "sshkit-backends-netssh_global"
  gem.require_paths = ["lib"]
  gem.version       = '0.2.1'

  gem.add_runtime_dependency('sshkit', '~> 1.11')

  gem.add_development_dependency('minitest', '>= 2.11.3', '< 5.11.0')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('turn')
  gem.add_development_dependency('mocha')
end
