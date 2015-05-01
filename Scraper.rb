require 'rubygems'
require 'bundler/setup'
require 'json' # for parsing and building api response data
require 'csv'  # for parsing locally-stored authentication data and exporting Eventbrite data
require 'rest-client'  # framework for calling APIs
require 'cgi'  # handles URL encoding for SF rest API calls

class Scrape

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
      previous_buffer = []
      current_buffer = []
      if prop[1].is_a? (Hash)
        current_buffer << prop[0]
        new_titles = parse_hash_titles(new_titles,current_buffer,previous_buffer,prop[1])
      else
        unless prop[1].nil?
          new_titles << prop[0]
        end
      end
    end
    return new_titles
  end

  #recursive method for parsing multiple levels of JSON document
  def parse_hash_titles(new_titles,current_buffer,previous_buffer,new_hash)
    previous_buffer = current_buffer[0..-1]
    new_hash.each do |prop|
      if prop[1].is_a? (Hash)
        current_buffer << prop[0]
        new_titles = parse_hash_titles(new_titles,current_buffer,previous_buffer,prop[1])
      else
        unless prop[1].nil?
          # important to prevent inappropriate buffer chaining
          current_buffer = previous_buffer
          new_titles << [current_buffer,prop[0]].join('.')
        end
      end
    end
    return new_titles
  end

  # writes CSV from json document using titles
  def write_csv(type, final_arr)
    csv_data = CSV.generate do |csv|
      val = []
      final_arr[0][0].each do |title|
        val << title
      end
      csv << val
      final_arr[1].each do |elem|
        elem.each do |doc|
          data = []
          json_doc = JSON.generate(doc)
          json_doc = JSON.parse(json_doc)
          final_arr[0][0].each do |key|
            key_array = key.split('.')
            data << get_nested_val(key_array,json_doc)
          end
          csv << data
        end
      end
    end
    File.write("data_dump/#{type}_details.csv",csv_data)
  end

  def get_nested_val(key_array,json_doc)
    current_doc = json_doc
    key_array.each do |key|
      unless current_doc[key].nil?
        current_doc = current_doc[key]
        @get_val = current_doc
      else
        return nil
      end
    end
    return @get_val
  end

  #given a particular type, returns the correct endpoint for api calls
  def get_api_endpoint(type_to_scrape, obj)
    token = ENV['eventbrite_api_key']
    organizer_id = ENV["eventbrite_organizer_id"]
    prefix = "https://www.eventbriteapi.com/v3"
    case type_to_scrape
    when "eid"
      endpoint = "#{prefix}/users/#{organizer_id}/owned_events/" \
        "?order_by=start_desc&token=#{token}"
    when "event"
      endpoint = "#{prefix}/events/#{obj}/?token=#{token}"
    when "attendee"
      endpoint = "#{prefix}/events/#{obj}/attendees/?token=#{token}&expand=" \
        "category,attendees,subcategory,format,venue,event" \
        ",ticket_classes,organizer,order,promotional_code"
    when "vid"
      endpoint = "#{prefix}/users/#{organizer_id}/venues/?token=#{token}"
    when "venue"
      endpoint = "#{prefix}/venues/#{obj}/?token=#{token}"
    end
  end

  # validate date formats: YYYY-MM-DD
  def validate_dates(dates)
    date_format = /(2009|201[0-5])-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])/
    dates.each do |d|
      date_format.match(d).nil? \
      ? false : true
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
      events = json_file["events"]
      #pull the pages most and least recent event dates
      most_recent= Date.parse events[0]["start"]["local"]
      least_recent = Date.parse events[-1]["start"]["local"]
      #nil-handling for no stop-date
      stop = most_recent + 1 if stop.nil?
      if stop > least_recent
        events.each do |event|
          current = Date.parse event["start"]["local"]
          eid << event["id"] if stop > current && start <= current
        end
      end
      json_file = turn_page(endpoint + "&page=#{page_number}")
    end until start > least_recent
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
    begin
      @response = RestClient.get url
      while @response.nil? do
        if @response.code == 200
          @response = RestClient.get url
        end
      end
    rescue => e
    end
    @json_file = JSON.parse(@response)
  end

  # process all eventbrite data (events & attendees) into Salesforce
  def all_to_salesforce(event_data,attendee_data)
    auth_vals = get_rest_authentication()
    campaign_id = campaigns_to_salesforce(event_data,auth_vals)
    contact_ids = contacts_to_salesforce(attendee_data,auth_vals)
    campaignmember_ids = campaignmembers_to_salesforce(attendee_data,auth_vals)
  end

  def campaigns_to_salesforce(data,auth_vals)
    push_data_to_salesforce("Campaign",data,auth_vals)
  end

  def contacts_to_salesforce(data,auth_vals)
    push_data_to_salesforce("Contact",data,auth_vals)
  end

  def campaignmembers_to_salesforce(data,auth_vals)
    push_data_to_salesforce("CampaignMember",data,auth_vals)
  end

  # potential method for handling some of the start-up functions in each of the
  # x_to_salesforce methods
  def get_json_payload(object_type,obj)
    case
    when object_type == "Campaign"
      csv = CSV.read('data/campaign_fields.csv')
    when object_type == "Contact"
      csv = CSV.read('data/contact_fields.csv')
    when object_type == "CampaignMember"
      csv = CSV.read('data/campaignmember_fields.csv')
    when object_type == "CampaignMemberPatch"
      csv = CSV.read("data/campaignmemberpatch_fields.csv")
    end
    payload = build_payload_from_csv(csv,obj)
    # Short-term solution to excessive titles and incorrect titles
    if object_type == "Campaign"
      payload["Name"] = payload["Name"][0..79] if payload["Name"].length > 80
    elsif object_type == "Contact"
      payload["Email"] = obj["order"]["email"] if obj["profile"]["email"].nil?
      payload["Email"] = payload["Email"].gsub(',','')
    end
    json_payload = JSON.generate(payload)
  end

  # initiate API authentication and return hash of auth values
  def get_rest_authentication()
    sf_oauth_prefix = ENV['sf_oauth_prefix']
    sf_oauth_endpoint = "#{sf_oauth_prefix}/services/oauth2/authorize"
    oauth_token_endpoint = "#{sf_oauth_prefix}/services/oauth2/token"
    client_id = ENV['sf_client_id']
    client_secret = ENV['sf_client_secret']
    username = ENV['sf_username']
    password = ENV['sf_password']
    auth_payload = "grant_type=password&client_id=#{client_id}" \
      "&client_secret=#{client_secret}" \
      "&username=#{username}&password=#{password}"
    params = {:accept => 'application/json'}
    @auth_response = RestClient.post oauth_token_endpoint, auth_payload, params
    auth_json = JSON.parse(@auth_response)
    auth_vals = {"access_token" => auth_json["access_token"],
      "instance_url" => auth_json["instance_url"]}
  end

  # test method for experimenting with Salesforce & Eventbrite REST API Calls
  def push_data_to_salesforce(object_type,data,auth_vals)
    instance_url = auth_vals["instance_url"]
    access_token = auth_vals["access_token"]
    data[0].each do |obj|
      obj = add_ids_to_campaignmember(obj,instance_url,access_token) if object_type == "CampaignMember"
      next if obj.nil?
      json_payload = get_json_payload(object_type,obj)
      query_response = search_salesforce(object_type,obj,instance_url,access_token)
      # rest api call parameters
      unless query_response == "[]" || query_response == '{"totalSize":0,"done":true,"records":[]}'
        if object_type == "CampaignMember"
          json_payload = get_json_payload("CampaignMemberPatch",obj)
          json_response = JSON.parse(query_response)
          response_id = json_response["records"][0]["Id"]
          base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/#{response_id}"
          response =
            rest_call("patch",base_uri,json_payload,access_token)
        else
          json_response = JSON.parse(query_response)[0]
          response_id = json_response["Id"]
          base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/#{response_id}"
          # prevent events from getting patched
          chapter = JSON.parse(json_payload)["Chapter__c"]
          unless chapter == "INSERT CHAPTER HERE" && object_type == "Campaign"
            response =
              rest_call("patch",base_uri,json_payload,access_token)
          end
        end
      else
        base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/"
        response = rest_call("post",base_uri,json_payload,access_token)
      end
    end
  end

  # encode a string for use in rest call
  def url_encode(string)
    string = CGI.escape string
  end

  def remove_non_ascii(string)
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
  def escape_characters(string)
    ['&','-','?','|','!',"'",'+'].each do |syn_char|
      string = string.gsub(syn_char,'\\\\' + "#{syn_char}")
    end
    return string
  end

  # adds Campaign and Contact Id info to CampaignMember payload before processing
  def add_ids_to_campaignmember(obj,instance_url,access_token)
    json_payload = nil
    campaign_id = obj["event"]["id"]
    contact_email = obj["profile"]["email"]
    contact_fn = escape_characters(obj["profile"]["first_name"])
    contact_ln = escape_characters(obj["profile"]["last_name"])
    contact_email = obj["order"]["email"] if contact_email.nil?
    contact_email = escape_characters(contact_email)
    checked_in = nil
    checked_in = "Responded" if obj["checked_in"]
    campaign_search_string =
      url_encode(
        "FIND {#{campaign_id}}" \
        " IN ALL FIELDS" \
        " RETURNING Campaign(Id)")
    contact_search_string =
      url_encode(
      "FIND {#{contact_fn}" \
      " AND #{contact_ln}" \
      " AND #{contact_email}}" \
      " IN ALL FIELDS" \
      " RETURNING Contact(Id)")
    campaign_base_uri = "#{instance_url}/services/data/v29.0/search/?q=#{campaign_search_string}"
    begin
      campaign_query_response = rest_call("get",campaign_base_uri,json_payload,access_token)
      @json_campaign = JSON.parse(campaign_query_response)[0]
    end until !@json_campaign.nil?
    contact_base_uri = "#{instance_url}/services/data/v29.0/search/?q=#{contact_search_string}"
    contact_query_response = rest_call("get",contact_base_uri,json_payload,access_token)
    json_contact = JSON.parse(contact_query_response)[0]
    unless json_contact.nil?
      obj.store("ContactId",json_contact["Id"])
      obj.store("CampaignId",@json_campaign["Id"])
      obj.store("Status",checked_in) unless checked_in.nil?
    else
      obj = nil
    end
    return obj
  end

  # search salesforce for Eventbrite data
  def search_salesforce(object_type,obj,instance_url,access_token)
    type = "search"
    case
    when object_type == "Campaign"
      campaign_id = obj["id"]
      search_string =
        url_encode(
          "FIND {#{campaign_id}}" \
          " IN ALL FIELDS" \
          " RETURNING #{object_type}(Id)")
    when object_type == "Contact"
      contact_fn = escape_characters(obj["profile"]["first_name"])
      contact_ln = escape_characters(obj["profile"]["last_name"])
      contact_email =  obj["profile"]["email"]
      contact_email = obj["order"]["email"] if contact_email.nil?
      contact_email = escape_characters(contact_email)
      search_string =
        url_encode(
          "FIND {#{contact_fn}" \
          " AND #{contact_ln}" \
          " AND #{contact_email}}" \
          " IN ALL FIELDS" \
          " RETURNING #{object_type}(Id)")
    puts search_string
    when object_type == "CampaignMember"
      contact_id = obj["ContactId"]
      campaign_id = obj["CampaignId"]
      type = "query"
      search_string =
        url_encode(
          "SELECT Id" \
          " FROM CampaignMember" \
          " WHERE CampaignId='#{campaign_id}'" \
          " AND ContactId='#{contact_id}'")
    end
    base_uri = "#{instance_url}/services/data/v29.0/#{type}/?q=#{search_string}"
    json_payload = nil
    query_response = rest_call("get",base_uri,json_payload,access_token)
    puts query_response
    return query_response
  end

  # method for calling rest api
  def rest_call(call,base_uri,json_payload,access_token)
    params =
      {"Authorization" => "Bearer #{access_token}",
      :content_type => 'application/json',
      :accept => 'application/json',
      :verify => false}
    case call
    when "get"
      response = rest_get(base_uri,params)
    when "post"
      response = rest_post(base_uri,json_payload,params)
    when "patch"
      response = rest_patch(base_uri,json_payload,params)
    end
    return response
  end

  # method for handling HTTP-GET calls
  def rest_get(base_uri,params)
    begin
      @response = RestClient.get(base_uri,params)
    rescue => e
      puts @response.code
    end
    return @response
  end

  # method for handling HTTP-POST calls
  def rest_post(base_uri,json_payload,params)
    begin
      @response = RestClient.post(base_uri,json_payload,params)
    rescue => e
      puts @response.code
    end
    return @response
  end

  # method for handling HTTP-PATCH calls
  # also, enforces "patch-only if field is empty" rule
  def rest_patch(base_uri,json_payload,params)
    begin
      @response = RestClient.patch(base_uri,json_payload,params)
    rescue => e
      puts @response.code
    end
    return @response
  end

  # reads csv and generates a hash payload for API calls
  def build_payload_from_csv(csv, obj)
    payload = {}
    csv.each do |row|
      payload.store(row.first,get_nested_val(row.last.split('.'),obj))
    end
    return payload
  end

end
