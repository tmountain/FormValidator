module Filters
  def filter_e_to_o(value)
    value.gsub("e", "o")
  end
end
{
:extension =>
  {
    :required => :hello,
    :filters  => :e_to_o
  }
}
