$LOAD_PATH << File.expand_path("lib", __dir__)
require 'dav4rack/version'

Gem::Specification.new do |s|
  s.name = 'dav4rack'
  s.version = DAV4Rack::VERSION
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/chrisroberts/dav4rack'
  s.description = 'WebDAV handler for Rack'
  s.license = "MIT"
  
  s.executables = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.files = `git ls-files -- lib/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'nokogiri', '>= 1.4.2'
  s.add_runtime_dependency 'uuidtools', '~> 2.1.1'
  s.add_runtime_dependency 'rack', '~> 2.0'
  s.add_runtime_dependency 'webrick'

  s.add_development_dependency("rspec", "~> 3.0")
  s.add_development_dependency("debug")
end
