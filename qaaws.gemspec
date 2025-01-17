Gem::Specification.new do |s|
  s.name = 'qaaws'
  s.version = '0.17.0'
  s.authors = ['Rob Goretsky']
  s.email = %w(robert.goretsky@gmail.com)
  s.summary = %q{Ruby Access to the SAP Business Objects Query As A Web Service interface}


  s.files = %w[
lib/qaaws/string_type_checks.rb
lib/qaaws/qaaws.rb
lib/qaaws/table.rb
lib/qaaws.rb
test/qaaws_test.rb
README
qaaws.gemspec
]

  s.require_paths = %w(lib)

  s.add_dependency 'nokogiri', '1.10.3'
  s.add_dependency 'savon', '2.12.0'
  s.add_dependency 'activesupport'
  s.add_dependency 'json', '~> 1.7'
  s.add_dependency 'i18n'
  s.add_development_dependency 'pry'

end
