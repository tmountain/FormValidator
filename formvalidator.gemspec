Gem::Specification.new do |s|
  s.name = %q{formvalidator}
  s.version = "0.1.5"
  s.date = Time.now
  s.summary = %q{FormValidator is a Ruby port of Perl's Data::FormValidator library.}
  s.author = %q{Travis Whitton}
  s.email = %q{tinymountain@gmail.com}
  s.homepage = %q{http://grub.ath.cx/formvalidator/}
  s.require_path = %q{.}
  s.autorequire = %q{formvalidator}
  s.files = Dir.glob('**/*') 
  s.has_rdoc = true
  s.rdoc_options = ["--main", "README.rdoc"]
  s.extra_rdoc_files = ["README.rdoc"]
  s.test_files = %w{tests/regress.rb}
end
