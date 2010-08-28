require "test/unit"
require "../formvalidator"

class TestValidator < Test::Unit::TestCase
  def setup
    @form = {
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
    @fv = FormValidator.new("testprofile.rb")
  end

  def test_valid
    res = @fv.validate(@form, :customer)
    assert_equal(
      ["age", "check_no", "city", "country", "email", "first_name",
       "home_phone", "last_name", "password", "paytype", "state",
       "street", "zipcode"],
      @fv.valid.keys.sort
    )
    assert_equal(false, res)
  end

  def test_invalid
    @fv.validate(@form, :customer)
    assert_equal({"fax"=>["american_phone"]}, @fv.invalid)
  end

  def test_missing
    @fv.validate(@form, :customer)
    assert_equal(["password_confirmation"], @fv.missing)
  end

  def test_unknown
    @fv.validate(@form, :customer)
    assert_equal([], @fv.unknown)
  end

  def test_optional
    fakecgi = {}
    def fakecgi.[](somevar)
      []
    end
    profile = {
      :optional => :somefield,
      :constraints => {
        :somefield => :phone
      }
    }
    @fv.validate(fakecgi, profile)
    assert_equal({}, @fv.invalid)
  end

  def test_required
    # define a profile with mixed strings and symbols
    profile = {
      :required => [:first_name, "last_name", "age"]
    }
    @fv.validate(@form, profile)
    assert_equal(["age", "first_name", "last_name"], @fv.valid.keys.sort)
    assert_equal([], @fv.missing)
    # define a profile with only a string
    profile = {
      :required => "ssn"
    }
    @fv.validate(@form, profile)
    assert_equal(["ssn"], @fv.missing)
    # define a profile with only a symbol
    profile = {
      :required => "ssn"
    }
    @fv.validate(@form, profile)
    assert_equal(["ssn"], @fv.missing)
  end

  def test_required_regexp
    profile = {
      :required_regexp => /name/
    }
    @fv.validate(@form, profile)
    assert_equal([], @fv.missing)
    form = {
      "my_name" => ""
    }
    @fv.validate(form, profile)
    assert_equal(["my_name"], @fv.missing)
  end
  
  def test_require_some
    form = {
      "city"       => "Gainesville",
      "state"      => "Fl",
      "zip"        => "",
      "first_name" => "Travis",
      "last_name"  => "Whitton"
    }
    profile = {
      :require_some => {
        :location => [3, %w{city state zip}],
        :name     => [2, %w{first_name last_name}]
      }
    }
    @fv.validate(form, profile)
    assert_equal(["location"], @fv.missing)
  end

  def test_defaults
    form = {
      "name" => "Travis"
    }
    # test symbols
    profile = {
      :defaults => { :country => "USA" }
    }
    @fv.validate(form, profile)
    assert_equal("USA", form["country"])
    # test strings
    profile = {
      :defaults => { "country" => "USA" }
    }
    @fv.validate(form, profile)
    assert_equal("USA", form["country"])
  end

  def test_dependencies
    form = {
      "city"    => "gainesville",
      "state"   => "FL",
      "zipcode" => "32608"
    }
    profile = {
      :optional => [:city, :state, :zipcode, :street],
      :dependencies => { :city => [:state, :zipcode] }
    }
    @fv.validate(form, profile)
    assert_equal([], @fv.missing)
    profile = {
      :optional => [:city, :state, :zipcode],
      :dependencies => { :city => [:state, :zipcode, :street] }
    }
    @fv.validate(form, profile)
    assert_equal(["street"], @fv.missing)
    form = {} 
    @fv.validate(form, profile)
    assert_equal([], @fv.missing)
    form = {
      "paytype" => "CC",
      "cc_type" => "VISA",
      "cc_exp"  => "02/04",
      "cc_num"  => "123456789",
    }
    profile = {
      :optional => [:paytype, :cc_type, :cc_exp, :cc_num],
      :dependencies => {
                         :paytype => { :CC    => [:cc_type, :cc_exp, :cc_num],
                                       :Check => :check_no }
                       }
    }
    @fv.validate(form, profile)
    assert_equal([], @fv.missing)
    form = {
      "paytype" => "Check"
    }
    @fv.validate(form, profile)
    assert_equal(["check_no"], @fv.missing)
  end

  def test_dependency_groups
    form = {
      "username" => "travis",
      "password" => "foo123"
    }
    profile = {
      :optional => [:username, :password],
      :dependency_groups => {
        :password_group => %w{username password}
      }
    }
    @fv.validate(form, profile)
    assert_equal([], @fv.missing)
    form = {
      "username" => "travis"
    }
    @fv.validate(form, profile)
    assert_equal(["password"], @fv.missing)
    form = {
      "password" => "foo123"
    }
    @fv.validate(form, profile)
    assert_equal(["username"], @fv.missing)
    form = {}
    @fv.validate(form, profile)
    assert_equal([], @fv.missing)
  end

  def test_filters
    form = {
      "first_name" => "    Travis    ",
      "last_name"  => "   whitton  ",
    }
    profile = {
      :optional => [:first_name, "last_name"],
      :filters => [:strip, :capitalize]
    }
    @fv.validate(form, profile)
    assert_equal("Travis", form["first_name"])
    assert_equal("Whitton", form["last_name"])
  end

  def test_field_filters
    form = {
      "first_name" => "   travis   ",
      "last_name"  => "   whitton   "
    }
    profile = {
      :optional => [:first_name, :last_name],
      :field_filters => {
        "first_name" => [:strip, :capitalize]
      }
    }
    @fv.validate(form, profile)
    assert_equal("Travis", form["first_name"])
    assert_equal("   whitton   ", form["last_name"])
  end

  def test_field_filter_regexp_map
    form = {
      "first_name" => "   travis   ",
      "last_name"  => "   whitton   ",
      "handle"     => "   dr_foo   "
    }
    profile = {
      :optional => [:first_name, :last_name, "handle"],
      :field_filter_regexp_map => {
        /name/ => [:strip, :capitalize]
      }
    }
    @fv.validate(form, profile)
    assert_equal("Travis", form["first_name"])
    assert_equal("Whitton", form["last_name"])
    assert_equal("   dr_foo   ", form["handle"])
  end

  def test_untaint_all_constraints
    form = {
      "ip" => "192.168.1.1"
    }
    form["ip"].taint
    profile = {
      :optional => :ip,
      :constraints => {
        :ip => :ip_address
      }
    }
    @fv.validate(form, profile)
    assert_equal(true, form["ip"].tainted?)
    form["ip"].taint
    profile = {
      :optional => :ip,
      :untaint_all_constraints => true,
      :constraints => {
        :ip => :ip_address
      }
    }
    @fv.validate(form, profile)
    assert_equal(false, form["ip"].tainted?)
  end

  def test_untaint_constraint_fields
    form = {
      "ip" => "192.168.1.1"
    }
    form["ip"].taint
    assert_equal(true, form["ip"].tainted?)
    profile = {
      :optional => :ip,
      :untaint_constraint_fields => :ip,
      :constraints => {
        :ip => :ip_address
      }
    }
    @fv.validate(form, profile)
    assert_equal(false, form["ip"].tainted?)
  end

  def test_hash_constructor
    profile = {
      :test => {
        :required => [ :foo ]
      }
    }
    fv = FormValidator.new(profile)
    assert(fv.validate({'foo' => 'bar'}, :test))
  end

  def test_constraint_regexp_map
    form = {
      "zipcode" => "32608"
    }
    profile = {
      :optional => :zipcode,
      :constraint_regexp_map => {
        /code/ => :zip
      }
    }
    @fv.validate(form, profile)
    assert_equal({}, @fv.invalid)
    form = {
      "zipcode" => "abcdef"
    }
    @fv.validate(form, profile)
    assert_equal({"zipcode" => ["zip"]}, @fv.invalid)
  end

  def test_constraints
    year = Time.new.year
    month = Time.new.month

    # CC num below is not real. It simply passes the checksum.
    form = {
      "cc_no"   => "378282246310005",
      "cc_type" => "AMEX",
      "cc_exp"  => "#{month}/#{year}"
    }

    profile = {
      :optional => %w{cc_no cc_type cc_exp},
      :constraints => {
        :cc_no => {
          :name       => "cc_test",
          :constraint => :cc_number,
          :params     => [:cc_no, :cc_type]
        }
      }
    }

    @fv.validate(form, profile)
    assert_equal({}, @fv.invalid)

    form = {
      "zip" => "32608-1234"
    }

    profile = {
      :optional => :zip,
      :constraints => {
        :zip => [
                  :zip,
                  {
                    :name       => "all_digits",
                    :constraint => /^\d+$/
                  }
                ]
      }
    }
    @fv.validate(form, profile)
    assert_equal({"zip"=>["all_digits"]}, @fv.invalid)

    form = {
      "num1" => "2",
      "num2" => "3"
    }

    even = proc{|n| n.to_i[0].zero?}

    profile = {
      :optional => [:num1, :num2],
      :constraints => {
        :num1 => even,
        :num2 => even
      }
    }

    @fv.validate(form, profile)
    assert_equal(["num2"], @fv.invalid.keys)
    assert_equal(["num1"], @fv.valid.keys)
  end

  def test_filter_strip()
    assert_equal("testing", @fv.filter_strip("  testing  "))
  end

  def test_filter_squeeze()
    assert_equal(" two spaces ", @fv.filter_squeeze("  two  spaces  "))
  end

  def test_filter_digit()
    assert_equal("123", @fv.filter_digit("abc123abc"))
  end

  def test_filter_alphanum()
    assert_equal("somewords", @fv.filter_alphanum("@$some words%$#"))
  end

  def test_filter_integer()
    assert_equal("+123", @fv.filter_integer("num = +123"))
  end

  def test_filter_pos_integer()
    assert_equal("+123", @fv.filter_pos_integer("num = +123"))
  end

  def test_filter_neg_integer()
    assert_equal("-123", @fv.filter_neg_integer("num = -123"))
  end

  def test_filter_decimal()
    assert_equal("+1.123", @fv.filter_decimal("float = +1.123!"))
  end

  def test_filter_pos_decimal()
    assert_equal("+1.23", @fv.filter_pos_decimal("float = +1.23!"))
  end

  def test_filter_neg_decimal()
    assert_equal("-1.23", @fv.filter_neg_decimal("float = -1.23!"))
  end

  def test_filter_dollars()
    assert_equal("20.00", @fv.filter_dollars("my worth = 20.00"))
  end

  def test_filter_phone()
    assert_equal("(123) 123-4567", @fv.filter_phone("number=(123) 123-4567"))
  end

  def test_filter_sql_wildcard()
    assert_equal("SOME SQL LIKE %", @fv.filter_sql_wildcard("SOME SQL LIKE *"))
  end

  def test_filter_quote()
    assert_equal('foo@bar\.com', @fv.filter_quote("foo@bar.com"))
  end

  def test_filter_downcase()
    assert_equal("i like ruby", @fv.filter_downcase("I LIKE RUBY"))
  end

  def test_filter_upcase()
    assert_equal("I LIKE RUBY", @fv.filter_upcase("i like ruby"))
  end

  def test_filter_capitalize()
    assert_equal("I like ruby", @fv.filter_capitalize("i like ruby"))
  end

  def test_match_email()
    assert_equal("whitton@atlantic.net", @fv.match_email("whitton@atlantic.net"))
    assert_nil(@fv.match_email("whitton"))
  end

  def test_match_state_or_province()
    assert_equal("FL", @fv.match_state_or_province(:FL))
    assert_equal("AB", @fv.match_state_or_province(:AB))
    assert_nil(@fv.match_state_or_province(:ABC))
  end

  def test_match_state()
    assert_equal("CA", @fv.match_state(:CA))
    assert_nil(@fv.match_state(:CAR))
  end
  
  def test_match_province()
    assert_equal("YK", @fv.match_province(:YK))
    assert_nil(@fv.match_state(:YKK))
  end

  def test_match_zip_or_postcode()
    assert_equal("32608", @fv.match_zip_or_postcode("32608"))
    assert_equal("G1K 6Z9", @fv.match_zip_or_postcode("G1K 6Z9"))
    assert_nil(@fv.match_zip_or_postcode("123"))
  end

  def test_match_postcode()
    assert_equal("G1K 6Z9", @fv.match_postcode("G1K 6Z9"))
    assert_nil(@fv.match_postcode("ABCDEFG"))
  end

  def test_match_zip()
    assert_equal("32609-1234", @fv.match_zip("32609-1234"))
    assert_nil(@fv.match_zip("ABCDEFG"))
  end

  def test_match_phone()
    assert_equal("123-4567", @fv.match_phone("123-4567"))
    assert_nil(@fv.match_phone("abc-defg"))
  end

  def test_match_american_phone()
    assert_equal("(123) 123-4567", @fv.match_american_phone("(123) 123-4567"))
    assert_nil(@fv.match_american_phone("(abc) abc-defg"))
  end

  def test_match_cc_exp()
    year = Time.new.year
    month = Time.new.month
    assert_equal("#{month}/#{year+1}", @fv.match_cc_exp("#{month}/#{year+1}"))
    assert_nil(@fv.match_cc_exp("#{month}/#{year}"))
  end

  def test_match_cc_type()
    assert_equal("Mastercard", @fv.match_cc_type("Mastercard"))
    assert_nil(@fv.match_cc_type("Foocard"))
  end
  
  def test_match_ip_address()
    assert_equal("192.168.1.1", @fv.match_ip_address("192.168.1.1"))
    assert_nil(@fv.match_ip_address("abc.def.ghi.jkl"))
  end
end
