require "../formvalidator"

form = {
  "first_name" => "Travis",
  "last_name"  => "whitton",
  "age"        => "22",
  "home_phone" => "home phone: (123) 456-7890",
  "fax"        => "some bogus fax",
  "street"     => "111 NW 1st Street",
  "city"       => "fakeville",
  "state"      => "FL",
  "zipcode"    => "32608-1234",
  "email"      => "whitton@atlantic.net",
  "password"   => "foo123",
  "paytype"    => "Check",
  "check_no"   => "123456789"
}

fv = FormValidator.new("profiles/my_profile.rb")
fv.validate(form, :customer)
puts "valid   -> " + fv.valid.inspect
puts "invalid -> " + fv.invalid.inspect
puts "missing -> " + fv.missing.inspect
puts "unknown -> " + fv.unknown.inspect
