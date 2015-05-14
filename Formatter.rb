require 'cgi'

module Formatter

# validate date formats: YYYY-MM-D
  def self.validate_dates(dates)
    date_format = /(2009|201[0-5])-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])/
    dates.each do |d|
      date_format.match(d).nil? \
        ? false : true
    end
  end

  # encode a string for use in rest call
  def self.url_encode(string)
    string = CGI.escape string
  end

  def self.remove_non_ascii(string)
    encoding_options = {
    :invalid           => :replace,  # Replace invalid byte sequences
    :undef             => :replace,  # Replace anything not defined in ASCII
    :replace           => '',        # Use a blank for those replacements
    :universal_newline => true       # Always break lines with \n
    }
    non_ascii_string.encode(Encoding.find('ASCII'), encoding_options)
  end

  # prevent non-standard characters from being URL-encoded improperly by adding escape-slashes
  # when refactoring -- make sure not to use gsub! as it may alter the original API data
  def self.escape_characters(string)
    ['&','?','|','!',"'",'+','_'].each do |syn_char|
      string = string.gsub(syn_char,'\\\\' + "#{syn_char}")
    end
    return string
  end

end
