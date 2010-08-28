require "../formvalidator"

form = {
  "hello" => "werld"
}

fv = FormValidator.new("profiles/extension.rb")
fv.validate(form, :extension)
puts "hello " + form["hello"]
