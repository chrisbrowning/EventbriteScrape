require './Scraper.rb'
require './Formatter.rb'
require './DataWriter.rb'
require './Salesforce.rb'
require 'rubygems'
require 'bundler/setup'
require 'figaro'
require 'optparse'

Figaro.application = Figaro::Application.new(environment: "production", path: "./config/application.yml")
Figaro.load

# Command-line switching options via optparse
ARGV << '-h' if ARGV.empty?
options = {}
optparser = OptionParser.new do |opts|
  opts.banner =
    "\n-----------\nEventbriteScrape\n-----------\n\nUsage:ruby EventbriteScrape.rb [options]\n\n"

  options[:datescrape] = nil
  opts.on("-d", "--date STARTDATE,[ENDDATE]",Array, "Scrape by dates") do |d|
    options[:datescrape] = d
  end

  options[:eventscrape] = nil
  opts.on("-e", "--event EID,...", Array, "Scrape a specific event using EID") do |e|
    options[:eventscrape] = e
  end

  options[:venuescrape] = false
  opts.on("-v", "--venue", "Scrape venues") do |v|
    options[:venuescrape] = true
  end

  options[:salesforcepush] = false
  opts.on("-S", "--salesforce", "Post results of extract to Salesforce") do |s|
    options[:salesforcepush] = true
  end

  opts.on_tail("-h", "--help", "Display this screen") do
    puts opts
    exit
  end
end.parse!

  if !options[:datescrape].nil? && !options[:salesforcepush]
    #check valid date format; if invalid, complain, and die.
    valid_date_format = Formatter.validate_dates(options[:datescrape])
    if !valid_date_format
      abort("Invalid date format. Try yyyy-mm-dd.")
    end

    eid = Scraper.new.get_eid_by_date(options[:datescrape])
    final_arr = Scraper.new.scrape_eventbrite("event",eid)
    attendee_arr = Scraper.new.scrape_eventbrite("attendee", eid)
    DataWriter.write_csv("event",final_arr)
    DataWriter.write_csv("attendee",attendee_arr)
  end

  if !options[:datescrape].nil? && options[:salesforcepush]
    #check valid date format; if invalid, complain, and die.
    valid_date_format = Formatter.validate_dates(options[:datescrape])
    if !valid_date_format
      abort("Invalid date format. Try yyyy-mm-dd.")
    end

    eid = Scraper.new.get_eid_by_date(options[:datescrape])
    event_data_and_titles = Scraper.new.scrape_eventbrite("event",eid)
    attendee_data_and_titles = Scraper.new.scrape_eventbrite("attendee", eid)
    event_data = event_data_and_titles[1]
    attendee_data = attendee_data_and_titles[1]
    Scraper.new.all_to_salesforce(event_data,attendee_data)
    DataWriter.write_csv("event",event_data_and_titles)
    DataWriter.write_csv("attendee",attendee_data_and_titles)
  end

  if !options[:eventscrape].nil? && !options[:salesforcepush]
    final_arr = Scraper.new.scrape_eventbrite("event",options[:eventscrape])
    attendee_arr = Scraper.new.scrape_eventbrite("attendee", options[:eventscrape])
    DataWriter.write_csv("event",final_arr)
    DataWriter.write_csv("attendee",attendee_arr)
  end

  if !options[:eventscrape].nil? && options[:salesforcepush]
    event_data_and_titles = Scraper.new.scrape_eventbrite("event",options[:eventscrape])
    attendee_data_and_titles = Scraper.new.scrape_eventbrite("attendee", options[:eventscrape])
    event_data = event_data_and_titles[1]
    attendee_data = attendee_data_and_titles[1]
    Salesforce.all_to_salesforce(event_data,attendee_data)
    DataWriter.write_csv("event",event_data_and_titles)
    DataWriter.write_csv("attendee",attendee_data_and_titles)
  end

  if options[:venuescrape]
    puts "Venue scrape is still under construction"
    vid = Scraper.new.get_vid()
    venue_data = Scraper.new.scrape_eventbrite("venue",vid)
    DataWriter.write_csv("venue",venue_data)
  end
