require 'rubygems'
require 'bundler/setup'
require './REST.rb'
require './Formatter.rb'
require './Salesforce.rb'
require 'json' # for parsing and building api response data
require 'csv'  # for parsing locally-stored authentication data and exporting Eventbrite data

class Scraper

  def scrape_eventbrite(type_to_scrape, arr_to_scrape)
    #json_arr   -> used to store all json objects from api responses
    #titles     -> aggregate array of all unique properties of the json responses
    #new_titles -> titles for the current json object under inspection
    #final_arr  -> a multi-dim array: final_arr =[titles],[json_arr]
    json_arr, titles, new_titles, final_arr = [],[],[],[]

    pagination = TRUE if type_to_scrape == "attendee"

    arr_to_scrape.each do |obj|
      endpoint = get_api_endpoint(type_to_scrape, obj)
      json_file = get_json(endpoint)
      #handles multiple-pages for api responses
      if pagination
        pages = get_page_data(json_file)
        while pages["page_count"] >= pages["page_number"]
          # puts @pages["page_number"]
          json_file["attendees"].each do |a|
            json_arr << a
            new_titles = scrape_titles(a)
            titles = titles | new_titles
          end
          unless pages["page_count"] == pages["page_number"]
            json_file = turn_page(endpoint + "&page=#{pages["page_number"]}")
            pages = get_page_data(json_file)
          else
            break
          end
        end
      else #single-page
        new_titles = scrape_titles(json_file)
        titles = titles | new_titles
        json_arr << json_file
      end
    end
  final_arr = [titles],[json_arr]
  end

  # reads pagination on Eventbrite API response
  def get_page_data(json_file)
    pages = {}
    pages["page_count"] = json_file["pagination"]["page_count"]
    pages["page_number"] = json_file["pagination"]["page_number"]
    return pages
  end

  # pulls title information from a hash-formatted JSON document
  def scrape_titles(json_file)
    new_titles = []
    json_file.each do |prop|
      @current_buffer = []
      if prop[1].is_a? (Hash)
        @current_buffer << prop[0]
        new_titles = parse_hash_titles(new_titles,prop[1])
      else
        unless prop[1].nil?
          new_titles << prop[0]
        end
      end
    end
    return new_titles
  end

  #recursive method for parsing multiple levels of JSON document
  def parse_hash_titles(new_titles,new_hash)
    new_hash.each do |prop|
      if prop[1].is_a? (Hash)
        @current_buffer << prop[0]
        new_titles = parse_hash_titles(new_titles,prop[1])
      else
        unless prop[1].nil?
          # important to prevent inappropriate buffer chaining
          new_titles << [@current_buffer,prop[0]].join('.')
        end
      end
    end
    @current_buffer.pop
    return new_titles
  end

  #given a particular type, returns the correct endpoint for api calls
  def get_api_endpoint(type_to_scrape, obj)
    organizer_id = ENV["eventbrite_organizer_id"]
    prefix = "https://www.eventbriteapi.com/v3"
    case type_to_scrape
    when "eid"
      return "#{prefix}/users/#{organizer_id}/owned_events/?"
    when "event"
      return "#{prefix}/events/#{obj}/"
    when "attendee"
      return "#{prefix}/events/#{obj}/attendees/?&expand=" \
        "category,attendees,subcategory,format,venue,event" \
        ",ticket_classes,organizer,order,promotional_code"
    when "vid"
      return "#{prefix}/users/#{organizer_id}/venues/"
    when "venue"
      return "#{prefix}/venues/#{obj}/"
    end
  end

  # loop through user_owned_events and return a list of eids for events within a
  # certain range
  def get_eid_by_date(date)
    start = Date.parse date[0]
    stop = Date.parse date[1] unless date[1].nil?
    eid = []
    endpoint = get_api_endpoint("eid",nil)
    json_file = get_json(endpoint)
    begin
      page_count = json_file["pagination"]["page_count"]
      page_number = json_file["pagination"]["page_number"]
      last_page = (page_count == page_number)
      events = json_file["events"]
      #pull the pages most and least recent event dates
      least_recent= Date.parse events[0]["start"]["local"]
      most_recent = Date.parse events.last["start"]["local"]
      #nil-handling for no stop-date
      stop = most_recent + 99 if date[1].nil?
      if start <= most_recent
        events.each do |event|
          current = Date.parse event["start"]["local"]
          eid << event["id"] if stop >= current && start <= current
        end
      end
      json_file = turn_page(endpoint + "&page=#{page_number}") unless last_page
    end until stop <= most_recent || last_page
    return eid
  end

  def get_vid()
    vid = []
    endpoint = get_api_endpoint("vid",nil)
    json_file = get_json(endpoint)
    begin
      page_count = json_file["pagination"]["page_count"]
      page_number = json_file["pagination"]["page_number"]
      last_page = (page_count == page_number)
      venues = json_file["venues"]
      venues.each do |venue|
        vid << venue["id"]
      end
      json_file = turn_page(endpoint + "&page=#{page_number}") unless last_page
    end until last_page
    return vid
  end

  #turns the page on a paginated Eventbrite API JSON document
  def turn_page(old_url)
    split_old_url = old_url.split('&page=')
    new_url_prefix = split_old_url.first + "&page="
    new_url = new_url_prefix + (split_old_url.last.to_i + 1).to_s
    json_file = get_json(new_url)
  end

  #rest api-calling method; returns api response as a json object
  def get_json(url)
    response = REST.get url, ENV['eventbrite_api_key']
    json_file = JSON.parse(response)
  end

end
