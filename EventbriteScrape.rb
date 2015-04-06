require 'json' 				# for parsing and building api response data
require 'csv'  				# for parsing locally-stored authentication data and exporting Eventbrite data
require 'rest-client' # framework for calling APIs
require 'optparse' 		# framework for applciation CLI
require 'cgi'					# handles URL encoding for SF rest API calls

class EventbriteScrape

	# read a single-column csv file with authentication data
	reader = CSV.open('key.csv')
	$token = reader.shift[0]
	$client_id = reader.shift[0]
	$client_secret = reader.shift[0]
	$organizer_id = reader.shift[0]
	$username = reader.shift[0]
	$pass = reader.shift[0]

	# not-sensitive auth values
	$oauth_prefix = 'https://test.salesforce.com/'
	$oauth_auth_endpoint = "#{$oauth_prefix}/services/oauth2/authorize"
	$oauth_token_endpoint = "#{$oauth_prefix}/services/oauth2/token"

	def scrape(type_to_scrape, arr_to_scrape)

		#json_arr   -> used to store all json objects from api responses
		#titles     -> aggregate array of all unique properties of the json responses
		#new_titles -> titles for the current json object under inspection
		#final_arr  -> a multi-dim array: final_arr =[titles],[json_arr]
		@json_arr, @titles, @new_titles, @final_arr = [],[],[],[]

		@pagination = TRUE if ["attendee","venue"].include?(type_to_scrape)

		arr_to_scrape.each do |obj|
		  @endpoint = get_api_endpoint(type_to_scrape, obj)
		  @json_file = get_json(@endpoint)
			#handles multiple-pages for api responses
			if @pagination
			  @pages = get_page_data(@json_file)
				while @pages["page_count"] >= @pages["page_number"]
					# puts @pages["page_number"]
					case
					when type_to_scrape == "attendee"
						@json_file["attendees"].each do |a|
							@json_arr << a
							@new_titles = scrape_titles(a)
							@titles = @titles | @new_titles
						end
					when type_to_scrape == "venue"
						@json_file["venues"].each do |v|
							@json_arr << v
							@new_titles = scrape_titles(v)
							@titles = @titles | @new_titles
						end
					end
					unless @pages["page_count"] == @pages["page_number"]
						@json_file = turn_page(@endpoint + "&page=#{@pages["page_number"]}")
						@pages = get_page_data(@json_file)
					else
						break
					end
				end
			else #single-page
				@new_titles = scrape_titles(@json_file)
				# puts @new_titles
				@titles = @titles | @new_titles
				# puts @titles
			  @json_arr << @json_file
			end
		end
		@final_arr = [@titles],[@json_arr]
	end

	# reads pagination on Eventbrite API response
	def get_page_data(json_file)
		@pages = {}
		@pages["page_count"] = json_file["pagination"]["page_count"]
		@pages["page_number"] = json_file["pagination"]["page_number"]
		return @pages
	end

	# recursive method for extracting json properties from json file
	# flagged for refactoring -- this is filthy, yuck!
	def scrape_titles(json_file)
	  @new_titles = []
		json_file.each do |property|
			@title = property[0]
		  @snippet = property[1]
			if @snippet.is_a? (Hash)
				@snippet.each do |sub|
					unless sub[1].nil?
						if sub[1].is_a? (Hash)
						  @sub_title = sub[0]
						  sub[1].each do |sub2|
								unless sub2[1].nil?
									if sub2[1].is_a? (Hash)
										@sub_sub_title = sub2[0]
										sub2[1].each do |sub3|
											unless sub3[1].nil?
												@new_titles << [@title,@sub_title,@sub_sub_title,sub3[0]].join('.')
											end
										end
									else
										@new_titles << [@title,@sub_title,sub2[0]].join('.')
									end
								end
						  end
					  else
							# puts "@title + @snippet[0] = " + @title + '.' + sub[0]
						  @new_titles << [@title,sub[0]].join('.')
					  end
					end
				end
			else
				unless @snippet.nil?
				# puts @title
			  	@new_titles << @title
				end
			end
		end
		# puts @new_titles
		return @new_titles
	end

	# writes CSV from json document using titles
	def write_csv(type, final_arr)
	  @csv_data = CSV.generate do |csv|
			@val = []
		  final_arr[0][0].each do |title|
			  @val << title
			end
			csv << @val
			final_arr[1].each do |elem|
				elem.each do |doc|
				  @data = []
				  # puts doc[0].is_a? (Hash)
				  @json_doc = JSON.generate(doc)
			  	@json_doc = JSON.parse(@json_doc)
				  final_arr[0][0].each do |key|
				    @key_array = key.split('.')
				  	@data << get_nested_val(@key_array,@json_doc)
			  	end
				csv << @data
			  end
			end
		end
		File.write("#{type}_details.csv",@csv_data)
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
		@prefix = "https://www.eventbriteapi.com/v3"
		case
		when type_to_scrape == "eid"
		  @endpoint = "#{@prefix}/users/#{$organizer_id}/owned_events/?status=ended&order_by=start_desc&token=#{$token}"
		when type_to_scrape == "event"
			@endpoint = "#{@prefix}/events/#{obj}/?token=#{$token}"
		when type_to_scrape == "attendee"
			@endpoint = "#{@prefix}/events/#{obj}/attendees/?token=#{$token}&expand=category,attendees,subcategory,format,venue,event,ticket_classes,organizer,order,promotional_code"
		when type_to_scrape == "venue"
			@endpoint = "#{@prefix}/users/#{$organizer_id}/venues/?token=#{$token}"
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
		@start = Date.parse date[0]
		@stop = Date.parse date[1] unless date[1].nil?
		eid = []
		@endpoint = get_api_endpoint("eid",nil)
		@json_file = get_json(@endpoint)
		begin
			@page_count = @json_file["pagination"]["page_count"]
			@page_number = @json_file["pagination"]["page_number"]
			@events = @json_file["events"]
			#pull the pages most and least recent event dates
			@most_recent= Date.parse @events[0]["start"]["local"]
			@least_recent = Date.parse @events[-1]["start"]["local"]
			#nil-handling for no stop-date
			@stop = @most_recent + 1 if @stop.nil?
		  if @stop > @least_recent
		    @events.each do |event|
					@current = Date.parse event["start"]["local"]
			    eid << event["id"] if @stop > @current && @start <= @current
			  end
			end
			@json_file = turn_page(@endpoint + "&page=#{@page_number}")
		end until @start > @least_recent
		return eid
  end

	#turns the page on a paginated Eventbrite API JSON document
  def turn_page(old_url)
		@split_old_url = old_url.split('&page=')
    @new_url_prefix = @split_old_url.first + "&page="
		@new_url = @new_url_prefix + (@split_old_url.last.to_i + 1).to_s
		@json_file = get_json(@new_url)
	end

	## rest api-calling method; returns api response as a json object
	def get_json(url)
		@response = RestClient.get url
		while @response.nil? do
			if @response.code == 200
				@response = RestClient.get url
			elsif @response.code == 503
				return 0
			else
				return 1
			end
		end
		@json_file = JSON.parse(@response)
	end

	# process all eventbrite data (events & attendees) into Salesforce
	def all_to_salesforce(event_data,attendee_data)
		@auth_vals = get_rest_authentication()
		@campaign_id = campaigns_to_salesforce(event_data,@auth_vals)
		@contact_ids = contacts_to_salesforce(attendee_data,@auth_vals)
		@campaignmember_ids = campaignmembers_to_salesforce(attendee_data,@auth_vals)
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
			@csv = CSV.read('campaign_fields.csv')
		when object_type == "Contact"
			@csv = CSV.read('contact_fields.csv')
		when object_type == "CampaignMember"
			@csv = CSV.read('campaignmember_fields.csv')
		end
		@payload = build_payload_from_csv(@csv,obj)
		@json_payload = JSON.generate(@payload)
	end

	# initiate API authentication and return hash of auth values
	def get_rest_authentication()
		@auth_response = RestClient.post $oauth_token_endpoint,
			"grant_type=password&client_id=#{$client_id}&client_secret=#{$client_secret}&username=#{$username}&password=#{$pass}",
			{:accept => 'application/json'}
		@auth_json = JSON.parse(@auth_response)
		@auth_vals = {"access_token" => @auth_json["access_token"],
			 "instance_url" => @auth_json["instance_url"]}
	end

	# test method for experimenting with Salesforce & Eventbrite REST API Calls
	def push_data_to_salesforce(object_type,data,auth_vals)
		@instance_url = auth_vals["instance_url"]
		@access_token = auth_vals["access_token"]
		data[0].each do |obj|
			obj = add_ids_to_campaignmember(obj,@instance_url,@access_token) if object_type == "CampaignMember"
			@json_payload = get_json_payload(object_type,obj)
			@query_response = search_salesforce(object_type,obj,@instance_url,@access_token)
			unless @query_response == "[]" || @query_response == '{"totalSize":0,"done":true,"records":[]}'
				if object_type == "CampaignMember"
					@json_response = JSON.parse(@query_response)
				else
					@json_response = JSON.parse(@query_response)[0]
				end
				# tentatively patch only-if object is not campaignmember
				# limited in what can be updated on CampaignMember
				@response_id = @json_response["Id"]
				@response = RestClient.patch("#{@instance_url}/services/data/v29.0/sobjects/#{object_type}/#{@response_id}", @json_payload,
				  {"Authorization" => "Bearer #{@access_token}",
					:content_type => 'application/json',
					:accept => 'application/json',
					:verify => false}) if object_type != "CampaignMember"
			else
				@response = RestClient.post("#{@instance_url}/services/data/v29.0/sobjects/#{object_type}/", @json_payload,
				  {"Authorization" => "Bearer #{@access_token}",
					:content_type => 'application/json',
					:accept => 'application/json',
					:verify => false})
				@json_response = JSON.parse(@response)
			end
		end
	end

	# prevent non-standard characters from being URL-encoded improperly by adding escape-slashes
	# when refactoring -- make sure not to use gsub! as it may alter the original API data
	def add_escape_characters(string)
		@escaped_string = string
		['-','&',','].each do |syn_char|
			@escaped_string = @escaped_string.gsub(syn_char,'\\\\' + "#{syn_char}")
		end
		return @escaped_string
	end

	# adds Campaign and Contact Id info to CampaignMember payload before processing
	def add_ids_to_campaignmember(obj,instance_url,access_token)
		@campaign_id = obj["event"]["id"]
		@contact_email = add_escape_characters(obj["profile"]["email"])
		@contact_fn = add_escape_characters(obj["profile"]["first_name"])
		@contact_ln = add_escape_characters(obj["profile"]["last_name"])
		@contact_email = add_escape_characters(obj["order"]["email"]) if @contact_email.nil?
		@campaign_search_string = CGI.escape "FIND {#{@campaign_id}} IN ALL FIELDS RETURNING Campaign(Id)"
		@contact_search_string = CGI.escape "FIND {#{@contact_fn} AND #{@contact_ln} AND #{@contact_email}} IN ALL FIELDS RETURNING Contact(Id)"
		@campaign_query_response = RestClient.get("#{instance_url}/services/data/v29.0/search/?q=#{@campaign_search_string}",
			{"Authorization" => "Bearer #{access_token}",
			:accept => 'application/json',
			:verify => false})
		@contact_query_response = RestClient.get("#{instance_url}/services/data/v29.0/search/?q=#{@contact_search_string}",
			{"Authorization" => "Bearer #{access_token}",
			:accept => 'application/json',
			:verify => false})
		@json_campaign = JSON.parse(@campaign_query_response)[0]
		@json_contact = JSON.parse(@contact_query_response)[0]
		obj.store("ContactId",@json_contact["Id"])
		obj.store("CampaignId",@json_campaign["Id"])
		return obj
	end

	# search salesforce for Eventbrite data
	def search_salesforce(object_type,obj,instance_url,access_token)
		@type = "search"
		case
		when object_type == "Campaign"
			@campaign_id = obj["id"]
			@search_string = CGI.escape "FIND {#{@campaign_id}} IN ALL FIELDS RETURNING #{object_type}(Id)"
		when object_type == "Contact"
			@contact_fn = add_escape_characters(obj["profile"]["first_name"])
			@contact_ln = add_escape_characters(obj["profile"]["last_name"])
			@contact_email =  add_escape_characters(obj["profile"]["email"])
			@contact_email = add_escape_characters(obj["order"]["email"]) if @contact_email.nil?
			# puts @contact_email
			@search_string = CGI.escape "FIND {#{@contact_fn} AND #{@contact_ln} AND #{@contact_email}} IN ALL FIELDS RETURNING #{object_type}(Id)"
		when object_type == "CampaignMember"
			@contact_id = obj["ContactId"]
			@campaign_id = obj["CampaignId"]
			@type = "query"
			@search_string = CGI.escape "Select Id from CampaignMember Where CampaignId='#{@campaign_id}' AND ContactId='#{@contact_id}'"
		end
		@query_response = RestClient.get("#{instance_url}/services/data/v29.0/#{@type}/?q=#{@search_string}",
			{"Authorization" => "Bearer #{access_token}",
			:accept => 'application/json',
			:verify => false})
		return @query_response
	end

	# reads csv and generates a hash payload for API calls
	def build_payload_from_csv(csv, obj)
			@payload = {}
			csv.each do |row|
				@payload.store(row.first,get_nested_val(row.last.split('.'),obj))
			end
			return @payload
	end

end

# Command-line switching options via optparse
ARGV << '-h' if ARGV.empty?
options = {}
optparser = OptionParser.new do |opts|
 	opts.banner = "\n-----------\nEventbriteScrape\n-----------\n\nUsage:ruby EventbriteScrape.rb [options]\n\n"

 	options[:datescrape] = nil
 	opts.on("-d", "--date STARTDATE [ENDDATE]",Array, "Scrape after a given date or between dates") do |d|
 		options[:datescrape] = d
	end

	options[:eventscrape] = nil
	opts.on("-e", "--event EID ...", Array, "Scrape a specific event based on EID") do |e|
		options[:eventscrape] = e
	end

	options[:venuescrape] = nil
	opts.on("-v", "--venue VID ...", Array, "Scrape a specific event based on VID") do |v|
		options[:venuescrape] = v
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

  if !options[:datescrape].nil?
	  #check valid date format; if invalid, complain, and die.
	  valid_date_format = EventbriteScrape.new.validate_dates(options[:datescrape])
	  if !valid_date_format
	    abort("Invalid date format. Try yyyy-mm-dd.")
	  end

    eid = EventbriteScrape.new.get_eid_by_date(options[:datescrape])
	  final_arr = EventbriteScrape.new.scrape("event",eid)
		attendee_arr = EventbriteScrape.new.scrape("attendee", eid)
	  EventbriteScrape.new.write_csv("event",final_arr)
		EventbriteScrape.new.write_csv("attendee",attendee_arr)
  end

  if !options[:eventscrape].nil? && !options[:salesforcepush]
		final_arr = EventbriteScrape.new.scrape("event",options[:eventscrape])
		attendee_arr = EventbriteScrape.new.scrape("attendee", options[:eventscrape])
		EventbriteScrape.new.write_csv("event",final_arr)
	  EventbriteScrape.new.write_csv("attendee",attendee_arr)
  end

	if !options[:eventscrape].nil? && options[:salesforcepush]
		event_data_and_titles = EventbriteScrape.new.scrape("event",options[:eventscrape])
		attendee_data_and_titles = EventbriteScrape.new.scrape("attendee", options[:eventscrape])
		event_data = event_data_and_titles[1]
		attendee_data = attendee_data_and_titles[1]
		EventbriteScrape.new.all_to_salesforce(event_data,attendee_data)
		EventbriteScrape.new.write_csv("event",event_data_and_titles)
	  EventbriteScrape.new.write_csv("attendee",attendee_data_and_titles)
	end

	if !options[:venuescrape].nil?
		puts "Venue scrape is still under construction"
	end
