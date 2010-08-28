{
:customer =>
  {
    :required_regexp         => /name/,
    :required                => [ :home_phone, :age, :password ],
    :optional                => %w{fax email paytype check_no country},
    :optional_regexp         => /street|city|state|zipcode/,
    :require_some            => { :check_or_cc => [1, %w{cc_num check_no}] },
    :dependencies            => { :paytype => { :CC    => [ :cc_type, :cc_exp ],
                                                :Check => :check_no },
                                  :street => [ :city, :state, :zipcode ]
                                },
    :dependency_groups       => { :password_group => [ :password,
                                                       :password_confirmation ]
                                },
    :filters                 => :strip,
    :field_filters           => { :home_phone => :phone,
                                  :check_no   => :digit,
                                  :cc_no      => :digit
                                },
    :field_filter_regexp_map => { /name/ => :capitalize },
    :constraints             => { :age   => /^1?\d{1,2}$/,
                                  :fax   => :american_phone,
                                  :state => :state_or_province,
                                  :email => :email },
    :defaults                => { :country => "USA" },
    :constraint_regexp_map   => { /code/ => :zip },
    :untaint_all_constraints => true
  }
}
