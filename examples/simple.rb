require "../formvalidator"

form = {
  "phone" => "home phone: (123) 456-7890",
  "zip"   => "32608-1234",
  "rogue" => "some unknown field"
}

profile = {
  :required      => [:name, :zip],
  :optional      => :phone,
  :filters       => :strip,
  :field_filters => { :phone => :phone },
  :constraints   => {
    :phone => :american_phone,
    :zip   => [
      :zip,
      {
        :name       => "pure_digit",
        :constraint => /^\d+$/
      }
    ]
  }
}

fv = FormValidator.new
fv.validate(form, profile)
puts fv.valid.inspect   # <== {"phone"=>"  (123) 456-7890"}
puts fv.invalid.inspect # <== {"zip"=>["pure_digit"]}
puts fv.missing.inspect # <== ["name"]
puts fv.unknown.inspect # <== ["rogue"]

