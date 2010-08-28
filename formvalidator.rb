class FormValidator
  VERSION = "0.1.5"

  # Constructor.
  def initialize(profile=nil)
    @profile_file = profile # File to load profile from
    @profiles     = nil # Hash of profiles

    # If profile is a hash, there's no need to load it from a file.
    if Hash === profile
      @profiles = @profile_file
      @profile_file = nil
    end
  end

  # This method runs all tests specified inside of profile on form.
  # It sets the valid, invalid, missing and unknown instance variables
  # to the appropriate values and then returns true if no errors occured
  # or false otherwise.
  def validate(form, profile)
    setup(form, profile)
    field_filters
    filters
    field_filter_regexp_map
    required
    required_regexp
    require_some
    optional
    optional_regexp
    delete_empty
    delete_unknown
    dependencies
    dependency_groups
    defaults
    untaint_constraint_fields
    untaint_all_constraints
    constraint_regexp_map
    constraints
    !(missing.length > 0 || invalid.length > 0 || unknown.length > 0)
  end

  # Returns a distinct list of missing fields.
  def missing
    @missing_fields.uniq.sort
  end
  
  # Returns a distinct list of unknown fields.
  def unknown
    (@unknown_fields - @invalid_fields.keys).uniq.sort
  end

  # Returns a hash of valid fields and their associated values
  def valid
    @form
  end

  # Returns a hash of invalid fields and their failed constraints
  def invalid
    @invalid_fields
  end

  private

  # Load profile with a hash describing valid input.
  def setup(form_data, profile)
    @untaint_all         = false # Untaint all constraints?
    @missing_fields      = [] # Contains missing fields
    @unknown_fields      = [] # Unknown fields
    @required_fields     = [] # Contains required fields
    @invalid_fields      = {} # Contains invalid fields
    @untaint_fields      = [] # Fields which should be untainted
    @require_some_fields = [] # Contains require_some fields
    @optional_fields     = [] # Contains optional fields
    @profile             = {} # Contains profile data from wherever it's loaded

    if Hash === profile
      @profile = profile
    else
      load_profiles if @profile_file
      @profile = @profiles[profile]
    end
    check_profile_syntax(@profile)
    @form = form_data
    @profile = convert_profile(@profile)
  end

  # This converts all Symbols in a profile to strings for internal use.
  # This is the magic behind why a profile can use symbols or strings to
  # define valid input; therefore, making everybody happy.
  def convert_profile(profile)
    profile.each do |key,value|
      unless Hash === profile[key]
        # Convert data to an array and turn symbols into strings.
        profile[key] = strify_array(value)
        # Turn single items back into single items.
        profile[key] = profile[key][0] unless Array === value
      else
        # Recurse hashes nested to an unlimited level and stringify them
        profile[key] = strify_hash(profile[key])
      end
    end
  end

  # [:a, :b, :c, [:d, :e, [:f, :g]]] -> ["a", "b", "c", ["d", "e", ["f", "g"]]]
  def strify_array(array)
    Array(array).map do |m|
      m = (Array === m) ? strify_array(m) : m
      m = (Hash === m) ? strify_hash(m) : m
      Symbol === m ? m.to_s : m
    end
  end

  # Stringifies all keys and elements of a hash.
  def strify_hash(hash)
    newhash = {}
    conv = lambda {|key| Symbol === key ? key.to_s : key}
    hash.each do |key,value|
      if Hash === value
        newhash[conv.call(key)] = strify_hash(value)
      else
        newhash[conv.call(key)] = strify_array(value)
        newhash.delete(key) if Symbol === key
        unless Array === value
          newhash[conv.call(key)] = newhash[conv.call(key)][0] 
        end
      end
    end
    newhash
  end

  # Does some checks on the profile file and loads it.
  def load_profiles
    file = @profile_file
    # File must exist.
    raise "No such file: #{file}" unless test(?f, file)
    # File must be readable.
    raise "Can't read #{file}" unless test(?r, file)
    mtime = File.stat(file).mtime
    # See if an already loaded profile has been modified.
    return if @profiles and @profiles_mtime <= mtime
    # Eval to turn it into a hash.
    fh = File.open(file)
    @profiles = eval(fh.read)
    fh.close
    # Die if it's not a hash.
    raise "Input profiles didn't return a Hash" unless Hash === @profiles
    @profiles_mtime = mtime
  end

  # Ensure that profile contains valid syntax.
  def check_profile_syntax(profile)
    raise "Invalid input profile: Must be a Hash" unless Hash === profile
    valid_profile_keys =
      [ :optional, :required, :required_regexp, :require_some,
        :optional_regexp, :constraints, :constraint_regexp_map,
        :dependencies, :dependency_groups, :defaults, :filters,
        :field_filters, :field_filter_regexp_map,
        :missing_optional_valid, :validator_packages,
        :untaint_constraint_fields, :untaint_all_constraints ]

    profile.keys.map do |key|
      unless valid_profile_keys.include?(key)
        raise "Invalid input profile: #{key} is not a valid profile key"
      end
    end
  end

  # This module contains all the valid methods that can be invoked from an
  # input profile. See the method definitions below for more information.
  module InputProfile
    # Takes an array, symbol, or string.
    #
    # Any fields in this list which are not present in the user input will be
    # reported as missing.
    #
    #    :required => [:name, :age, :phone]
    def required
      Array(@profile[:required]).each do |field|
        @required_fields << field
        @missing_fields.push(field) if @form[field].to_s.empty?
      end
      @missing_fields
    end

    # Takes an array, symbol, or string.
    #
    # Any fields in this list which are present in the form hash will go
    # through any specified constraint checks and filters. Any fields that
    # aren't in the optional or required list are reported as unknown and
    # deleted from the valid hash.
    #
    #     :optional => [:name, :age, :phone]
    def optional
      Array(@profile[:optional]).each do |field|
        @optional_fields << field unless @optional_fields.include?(field)
      end
      @optional_fields
    end

    # Takes a regular expression.
    #
    # Specifies additional fieds which are required. If a given form element
    # matches the regexp, it must have data, or it will be reported in the
    # missing field list.
    #
    #     :required_regexp => /name/
    def required_regexp
      @form.keys.each do |elem|
        Array(@profile[:required_regexp]).each do |regexp|
          regexp = Regexp.new(regexp)
          if elem =~ regexp
            @required_fields << elem unless @required_fields.include?(elem)
            @missing_fields.push(elem) if @form[elem].to_s.empty?
          end
        end
      end
      @missing_fields
    end

    # Takes a regular expression.
    #
    # Any form fields that match the regexp specified are added to the list
    # of optional fields.
    #
    #     :required_regexp => /name/
    def optional_regexp
      @form.keys.each do |elem|
        Array(@profile[:optional_regexp]).each do |regexp|
          regexp = Regexp.new(regexp)
          if elem =~ regexp
            @optional_fields << elem unless @optional_fields.include?(elem)
          end
        end
      end
      @optional_fields
    end

    # Takes a hash with each key pointing to an array.
    #
    # The first field in the array is the number of fields that must be filled.
    # The field is an array of fields to choose from. If the required number
    # of fields are not found, the key name is reported in the list of missing
    # fields.
    #
    #     :require_some => { :check_or_cc => [1, %w{cc_num check_no}] }
    def require_some
      return nil unless Hash === @profile[:require_some]
      @profile[:require_some].keys.each do |group|
        enough = 0
        num_to_require, fields = @profile[:require_some][group]
        fields.each do |field|
          unless @require_some_fields.include?(field)
            @require_some_fields << field
          end
          enough += 1 unless @form[field].to_s.empty?
        end
        @missing_fields.push(group.to_s) unless (enough >= num_to_require)
      end
      @missing_fields
    end

    # Takes a hash.
    #
    # Fills in defaults but does not override required fields.
    #
    #     :defaults => { :country => "USA" }
    def defaults
      return nil unless Hash === @profile[:defaults]
      keys_defaulted = []
      @profile[:defaults].each do |key,value|
        if @form[key].to_s.empty?
          @form[key] = value.to_s
          keys_defaulted.push(key)
        end
      end
      keys_defaulted
    end

    # Takes a hash.
    #
    # This hash which contains dependencies information. This is for the case
    # where one optional fields has other requirements. The dependencies can be
    # specified with an array. For example, if you enter your credit card
    # number, the field cc_exp and cc_type should also be present. If the
    # dependencies are specified with a hash then the additional constraint is
    # added that the optional field must equal a key on the form for the
    # dependencies to be added.
    #
    #     :dependencies => { :paytype => { :CC => [ :cc_type, :cc_exp ],
    #                                      :Check => :check_no
    #                                    }}
    #
    #     :dependencies => { :street => [ :city, :state, :zipcode ] }
    def dependencies
      return nil unless Hash === @profile[:dependencies]
      @profile[:dependencies].each do |field,deps|
        if Hash === deps
          deps.keys.each do |key|
            if @form[field].to_s == key
              Array(deps[key]).each do |dep|
                  @missing_fields.push(dep) if @form[dep].to_s.empty?
              end
            end
          end
        else
          if not @form[field].to_s.empty?
            Array(deps).each do |dep|
              @missing_fields.push(dep) if @form[dep].to_s.empty?
            end
          end
        end
      end
      @missing_fields
    end

    # Takes a hash pointing to an array.
    #
    # If no fields are filled, then fine, but if any fields are filled, then
    # all must be filled.
    #
    #     :dependency_groups => { :password_group => [ :pass1, :pass2 ] }
    def dependency_groups
      return nil unless Hash === @profile[:dependency_groups]
      require_all = false
      @profile[:dependency_groups].values.each do |val|
        require_all = true unless val.select{|group| @form[group]}.empty?
      end
      if require_all
        @profile[:dependency_groups].values.each do |deps|
          deps.each do |dep|
            @missing_fields.push(dep) if @form[dep].to_s.empty?
          end
        end
      end
      @missing_fields
    end

    # Takes an array, symbol, or string.
    #
    # Specified filters will be applied to ALL fields.
    #
    #     :filters => :strip
    def filters
      Array(@profile[:filters]).each do |filter|
        if respond_to?("filter_#{filter}".intern)
          @form.keys.each do |field|
            # If a key has multiple elements, apply filter to each element
            if Array(@form[field]).length > 1
              @form[field].each_index do |i|
                elem = @form[field][i]
                @form[field][i] = self.send("filter_#{filter}".intern, elem)
              end
            else
              if not @form[field].to_s.empty?
                @form[field] =
                  self.send("filter_#{filter}".intern, @form[field].to_s)
              end
            end
          end
        end
      end
      @form
    end

    # Takes a hash.
    #
    # Applies one or more filters to the specified field.
    # See FormValidator::Filters for a list of builtin filters.
    #
    #     :field_filters => { :home_phone => :phone }
    def field_filters
      Array(@profile[:field_filters]).each do |field,filters|
        Array(filters).each do |filter|
          if respond_to?("filter_#{filter}".intern)
            # If a key has multiple elements, apply filter to each element
            if Array(@form[field]).length > 1
              @form[field].each_index do |i|
                elem = @form[field][i]
                @form[field][i] = self.send("filter_#{filter}".intern, elem)
              end
            else
              @form[field] =
                self.send("filter_#{filter}".intern, @form[field].to_s)
            end
          end
        end
      end
      @form
    end

    # Takes a regexp.
    #
    # Applies one or more filters to fields matching regexp.
    #
    #     :field_filter_regexp_map => { /name/ => :capitalize }
    def field_filter_regexp_map
      Array(@profile[:field_filter_regexp_map]).each do |re,filters|
        Array(filters).each do |filter|
          if respond_to?("filter_#{filter}".intern)
            @form.keys.select {|key| key =~ re}.each do |match|
              # If a key has multiple elements, apply filter to each element
              if Array(@form[match]).length > 1
                @form[match].each_index do |i|
                  elem = @form[match][i]
                  @form[match][i] = self.send("filter_#{filter}".intern, elem)
                end
              else
                @form[match] =
                  self.send("filter_#{filter}".intern, @form[match].to_s)
              end
            end
          end
        end
      end
      @form
    end

    # Takes true.
    #
    # If this is set, all fields which pass a constraint check are assigned
    # the return value of the constraint check, and their values are untainted.
    # This is overridden by untaint_constraint_fields.
    #
    #     :untaint_all_constraints => true
    def untaint_all_constraints
      if @profile[:untaint_all_constraints]
        @untaint_all = true unless @profile[:untaint_constraint_fields]
      end
    end

    # Takes an array, symbol, or string.
    #
    # Any field found in this array will be assigned the return value
    # of the constraint check it passes, and it's value will be untainted.
    #
    #     :untaint_constraint_fields => %w{ name age }
    def untaint_constraint_fields
      Array(@profile[:untaint_constraint_fields]).each do |field|
        @untaint_fields.push(field)
      end
    end

    # Takes a hash.
    #
    # Applies constraints to fields matching regexp and adds failed fields to
    # the list of invalid fields. If untainting is enabled then the form
    # element will be set to the result of the constraint method.
    #
    #     :constraint_regexp_map => { /code/ => :zip }
    def constraint_regexp_map
      return nil unless Hash === @profile[:constraint_regexp_map]
      @profile[:constraint_regexp_map].each do |re,constraint|
        re = Regexp.new(re)
        @form.keys.select {|key| key =~ re}.each do |match|
          unless @form[match].to_s.empty?
            do_constraint(match, [constraint].flatten) 
          end
        end
      end
    end

    # Takes a hash.
    #
    # Apply constraint to each key and add failed fields to the invalid list.
    # If untainting is enabled then the form element will be set to the result
    # of the constraint method. Valid constraints can be one of the following:
    # * Array
    #     Any constraint types listed below can be applied in series.
    # * Builtin constraint function (See: FormValidator::Constraints)
    #     :fax => :american_phone
    # * Regular expression
    #     :age => /^1?\d{1,2}$/
    # * Proc object
    #     :num => proc {|n| ((n % 2).zero?) ? n : nil}
    # * Hash - used to send multiple args or name an unnamed constraint
    #     # pass cc_no and cc_type in as arguments to cc_number constraint
    #     # and set {"cc_no" => ["cc_test"]} in failed hash if constraint fails.
    #     :cc_no => {
    #       :name       => "cc_test",
    #       :constraint => :cc_number,
    #       :params     => [:cc_no, :cc_type]
    #     }
    #
    #     # If age coming in off the form is not all digits then set
    #     # {"age" => ["all_digits"]} in the failed hash.
    #     :age => {
    #       :name       => "all_digits",
    #       :constraint => /^\d+$/
    #     }
    #
    #     :constraints => { :age => /^1?\d{1,2}$/ }
    #     :constraints => { :zipcode    => [:zip, /^\d+/],
    #                       :fax        => :american_phone,
    #                       :email_addr => :email }
    def constraints
      return nil unless Hash === @profile[:constraints]
      @profile[:constraints].each do |key,constraint|
        do_constraint(key, [constraint].flatten) unless @form[key].to_s.empty?
      end
    end
  end # module InputProfile

  module ConstraintHelpers
    # Helper method to figure out what kind of constraint is being run.
    # Valid constraint objects are String, Hash, Array, Proc, and Regexp.
    def do_constraint(key, constraints)
      constraints.each do |constraint|
        type = constraint.class.to_s.intern
        case type
          when :String
            apply_string_constraint(key, constraint)
          when :Hash
            apply_hash_constraint(key, constraint)
          when :Proc
            apply_proc_constraint(key, constraint)
          when :Regexp
            apply_regexp_constraint(key, constraint) 
        end
      end
    end

    # Delete empty fields.
    def delete_empty
      @form.keys.each do |key|
        @form.delete(key) if @form[key].to_s.empty?
      end
    end

     # Find unknown fields and delete them from the form.
    def delete_unknown
      @unknown_fields =
        @form.keys - @required_fields - @optional_fields - @require_some_fields
      @unknown_fields.each {|field| @form.delete(field)}
    end

    # Indicates if @form[key] is scheduled to be untainted.
    def untaint?(key)
      @untaint_all || @untaint_fields.include?(key)
    end

    # Applies a builtin constraint to form[key]
    def apply_string_constraint(key, constraint)
      ### New code to handle multiple elements (beware!)
      if Array(@form[key]).length > 1
        index = 0
        Array(@form[key]).each do |value|
          res = self.send("match_#{constraint}".intern, @form[key][index].to_s)
          if res
            if untaint?(key)
              @form[key][index] = res
              @form[key][index].untaint
            end
          else
            @form[key].delete_at(index)
            @invalid_fields[key] ||= []
            unless @invalid_fields[key].include?(constraint)
              @invalid_fields[key].push(constraint) 
            end
            nil
          end
          index += 1
        end
      ### End new code
      else
        res = self.send("match_#{constraint}".intern, @form[key].to_s)
        if res
          if untaint?(key)
            @form[key] = res 
            @form[key].untaint
          end
        else
          @form.delete(key)
          @invalid_fields[key] ||= []
          unless @invalid_fields[key].include?(constraint)
            @invalid_fields[key].push(constraint) 
          end
          nil
        end
      end
    end

    # Applies regexp constraint to form[key]
    def apply_regexp_constraint(key, constraint)
      ### New code to handle multiple elements (beware!)
      if Array(@form[key]).length > 1
        index = 0
        Array(@form[key]).each do |value|
          m = constraint.match(@form[key][index].to_s)
          if m
            if untaint?(key)
              @form[key][index] = m[0]
              @form[key][index].untaint
            end
          else
            @form[key].delete_at(index)
            @invalid_fields[key] ||= []
            unless @invalid_fields[key].include?(constraint.inspect)
              @invalid_fields[key].push(constraint.inspect)
            end
            nil
          end
          index += 1
        end
      ### End new code
      else
        m = constraint.match(@form[key].to_s)
        if m
          if untaint?(key)
            @form[key] = m[0]
            @form[key].untaint
          end
        else
          @form.delete(key)
          @invalid_fields[key] ||= []
          unless @invalid_fields[key].include?(constraint.inspect)
            @invalid_fields[key].push(constraint.inspect)
          end
          nil
        end
      end
    end

    # applies a proc constraint to form[key]
    def apply_proc_constraint(key, constraint)
      if res = constraint.call(@form[key])
        if untaint?(key)
          @form[key] = res 
          @form[key].untaint
        end
      else
        @form.delete(key)
        @invalid_fields[key] ||= []
        unless @invalid_fields[key].include?(constraint.inspect)
          @invalid_fields[key].push(constraint.inspect)
        end
        nil
      end
    end

    # A hash allows you to send multiple arguments to a constraint.
    # constraint can be a builtin constraint, regexp, or a proc object.
    # params is a list of form fields to be fed into the constraint or proc.
    # If an optional name field is specified then it will be listed as
    # the failed constraint in the invalid_fields hash.
    def apply_hash_constraint(key, constraint)
      name     = constraint["name"]
      action   = constraint["constraint"]
      params   = constraint["params"]
      res      = false
      skip_end = false

      # In order to call a builtin or proc, params and action must be present.
      if action and params
        arg = params.map {|m| @form[m]}
        if String === action
          res = self.send("match_#{action}".intern, *arg)
        elsif Proc === action
          res = action.call(*arg)
        end
      end

      if Regexp === action
        ### New code to handle multiple elements (beware!)
        if Array(@form[key]).length > 1
          index = 0
          skip_end = true
          Array(@form[key]).each do |value|
            m = action.match(value)
            res = m[0] if m
            if res
              @form[key][index] = res if untaint?(key)
            else
              @form[key].delete_at(index)
              constraint = (name) ? name : constraint
              @invalid_fields[key] ||= []
              unless @invalid_fields[key].include?(constraint)
                @invalid_fields[key].push(constraint) 
              end
              nil
            end
            index += 1
          end
        ### End new code
        else
          m = action.match(@form[key].to_s)
          res = m[0] if m
        end
      end

      if not skip_end
        if res
          @form[key] = res if untaint?(key)
        else
          @form.delete(key)
          constraint = (name) ? name : constraint
          @invalid_fields[key] ||= []
          unless @invalid_fields[key].include?(constraint)
            @invalid_fields[key].push(constraint) 
          end
          nil
        end
      end
    end
  end # module ConstraintHelpers

  module Filters
    # Remove white space at the front and end of the fields.
    def filter_strip(value)
      value.strip
    end

    # Runs of white space are replaced by a single space.
    def filter_squeeze(value)
      value.squeeze(" ")
    end

    # Remove non digits characters from the input.
    def filter_digit(value)
      value.gsub(/\D/, "")
    end

    # Remove non alphanumerical characters from the input.
    def filter_alphanum(value)
      value.gsub(/\W/, "")
    end

    # Extract from its input a valid integer number.
    def filter_integer(value)
      value.gsub(/[^\d+-]/, "")
    end

    # Extract from its input a valid positive integer number.
    def filter_pos_integer(value)
      value.gsub!(/[^\d+]/, "")
      value.scan(/\+?\d+/).to_s
    end

    # Extract from its input a valid negative integer number.
    def filter_neg_integer(value)
      value.gsub!(/[^\d-]/, "")
      value.scan(/\-?\d+/).to_s
    end

    # Extract from its input a valid decimal number.
    def filter_decimal(value)
      value.tr!(',', '.')
      value.gsub!(/[^\d.+-]/, "")
      value.scan(/([-+]?\d+\.?\d*)/).to_s
    end

    # Extract from its input a valid positive decimal number.
    def filter_pos_decimal(value)
      value.tr!(',', '.')
      value.gsub!(/[^\d.+]/, "")
      value.scan(/(\+?\d+\.?\d*)/).to_s
    end

    # Extract from its input a valid negative decimal number.
    def filter_neg_decimal(value)
      value.tr!(',', '.')
      value.gsub!(/[^\d.-]/, "")
      value.scan(/(-\d+\.?\d*)/).to_s
    end

    # Extract from its input a valid number to express dollars like currency.
    def filter_dollars(value)
      value.tr!(',', '.')
      value.gsub!(/[^\d.+-]/, "")
      value.scan(/(\d+\.?\d?\d?)/).to_s
    end

    # Filters out characters which aren't valid for an phone number. (Only
    # accept digits [0-9], space, comma, minus, parenthesis, period and pound.
    def filter_phone(value)
      value.gsub(/[^\d,\(\)\.\s,\-#]/, "")
    end

    # Transforms shell glob wildcard (*) to the SQL like wildcard (%).
    def filter_sql_wildcard(value)
      value.tr('*', '%')
    end

    # Quotes special characters.
    def filter_quote(value)
      Regexp.quote(value)
    end

    # Calls the downcase method on its input.
    def filter_downcase(value)
      value.downcase
    end

    # Calls the upcase method on its input.
    def filter_upcase(value)
      value.upcase
    end

    # Calls the capitalize method on its input.
    def filter_capitalize(value)
      value.capitalize
    end
  end # module Filters

  module Constraints
    # Valid US state abbreviations.
    STATES = [
      :AL, :AK, :AZ, :AR, :CA, :CO, :CT, :DE, :FL, :GA, :HI, :ID, :IL, :IN,
      :IA, :KS, :KY, :LA, :ME, :MD, :MA, :MI, :MN, :MS, :MO, :MT, :NE, :NV,
      :NH, :NJ, :NM, :NY, :NC, :ND, :OH, :OK, :OR, :PA, :PR, :RI, :SC, :SD,
      :TN, :TX, :UT, :VT, :VA, :WA, :WV, :WI, :WY, :DC, :AP, :FP, :FPO, :APO,
      :GU, :VI ]
    # Valid Canadian province abbreviations.
    PROVINCES = [
      :AB, :BC, :MB, :NB, :NF, :NS, :NT, :ON, :PE, :QC, :SK, :YT, :YK ]

    # Sloppy matches a valid email address.
    def match_email(email)
      regexp = Regexp.new('^\S+@\w+(\.\w+)*$')
      match = regexp.match(email)
      match ? match[0] : nil
    end

    # Matches a US state or Canadian province.
    def match_state_or_province(value)
      match_state(value) || match_province(value)
    end

    # Matches a US state.
    def match_state(state)
      state = (state.class == String) ? state.intern : state
      index = STATES.index(state)
      (index) ? STATES[index].to_s : nil
    end

    # Matches a Canadian province.
    def match_province(prov)
      prov = (prov.class == String) ? prov.intern : prov
      index = PROVINCES.index(prov)
      (index) ? PROVINCES[index].to_s : nil
    end

    # Matches a Canadian postal code or US zipcode.
    def match_zip_or_postcode(code)
      match_zip(code) || match_postcode(code)
    end

    # Matches a Canadian postal code.
    def match_postcode(code)
      regexp = Regexp.new('^([ABCEGHJKLMNPRSTVXYabceghjklmnprstvxy]
                           [_\W]*\d[_\W]*[A-Za-z][_\W]*[- ]?[_\W]*\d[_\W]*
                           [A-Za-z][_\W]*\d[_\W]*)$', Regexp::EXTENDED)
      match = regexp.match(code)
      match ? match[0] : nil
    end

    # Matches a US zipcode.
    def match_zip(code)
      regexp = Regexp.new('^(\s*\d{5}(?:[-]\d{4})?\s*)$')
      match = regexp.match(code)
      match ? match[0] : nil
    end

    # Matches a generic phone number.
    def match_phone(number)
      regexp = Regexp.new('^(\D*\d\D*){6,}$')
      match = regexp.match(number)
      match ? match[0] : nil
    end

    # Matches a standard american phone number.
    def match_american_phone(number)
      regexp = Regexp.new('^(\D*\d\D*){7,}$')
      match = regexp.match(number)
      match ? match[0] : nil
    end

    # The number is checked only for plausibility, it checks if the number
    # could be valid for a type of card by checking the checksum and looking at
    # the number of digits and the number of digits of the number..
    def match_cc_number(card, card_type)
      orig_card  = card
      card_type  = card_type.to_s
      index      = nil
      digit      = nil
      multiplier = 2
      sum        = 0
      return nil if card.length == 0
      return nil unless card_type =~ /^[admv]/i
      # Check the card type.
      return nil if ((card_type =~ /^v/i && card[0,1] != "4") ||
                     (card_type =~ /^m/i && card[0,2] !~ /^51|55$/) ||
                     (card_type =~ /^d/i && card[0,4] !~ "6011") ||
                     (card_type =~ /^a/i && card[0,2] !~ /^34|37$/))
      card.gsub!(" ", "")
      return nil if card !~ /^\d+$/
      digit = card[0,1]
      index = (card.length-1)
      # Check for the valid number of digits.
      return nil if ((digit == "3" && index != 14) ||
                     (digit == "4" && index != 12 && index != 15) ||
                     (digit == "5" && index != 15) ||
                     (digit == "6" && index != 13 && index != 15))
      (index-1).downto(0) do |i|
        digit = card[i, 1].to_i
        product = multiplier * digit
        sum += (product > 9) ? (product-9) : product
        multiplier = 3 - multiplier
      end
      sum %= 10
      sum = 10 - sum unless sum == 0
      if sum.to_s == card[-1,1]
        match = /^([\d\s]*)$/.match(orig_card)
        return match ? match[1] : nil
      end
    end

    # This checks if the input is in the format MM/YY or MM/YYYY and if the MM
    # part is a valid month (1-12) and if that date is not in the past.
    def match_cc_exp(val)
      matched_month = matched_year = nil
      month, year = val.split("/")
      return nil if (matched_month = month.scan(/^\d+$/).to_s).empty?
      return nil if (matched_year = year.scan(/^\d+$/).to_s).empty?
      year = year.to_i
      month = month.to_i
      year += (year < 70) ? 2000 : 1900 if year < 1900
      now = Time.new.year
      return nil if (year < now) || (year == now && month <= Time.new.month)
      "#{matched_month}/#{matched_year}"
    end

    # This checks to see if the credit card type begins with a M, V, A, or D.
    def match_cc_type(val)
      (!val.scan(/^[MVAD].*$/i).empty?) ? val : nil
    end

    # This matches a valid IP address(version 4).
    def match_ip_address(val)
      regexp = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
      match = regexp.match(val)
      error = false
      if match
        1.upto(4) do |i|
          error = true unless (match[i].to_i >= 0 && match[i].to_i <= 255)
        end
      else
        error = true
      end
      error ? nil : match[0]
    end
  end # module Constraints

  include InputProfile
  include Filters
  include Constraints
  include ConstraintHelpers
end
