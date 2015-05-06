require 'json'
require 'csv'
require './Searcher.rb'
require './Formatter.rb'
require './REST.rb'


module Salesforce

  # process all eventbrite data (events & attendees) into Salesforce
  def self.all_to_salesforce(event_data,attendee_data)
    auth_vals = Salesforce.get_rest_authentication()
    campaign_id = Salesforce.campaigns_to_salesforce(event_data,auth_vals)
    contact_ids = Salesforce.contacts_to_salesforce(attendee_data,auth_vals)
    campaignmember_ids = Salesforce.campaignmembers_to_salesforce(attendee_data,auth_vals)
  end

  def self.campaigns_to_salesforce(data,auth_vals)
    Salesforce.push_data_to_salesforce("Campaign",data,auth_vals)
  end

  def self.contacts_to_salesforce(data,auth_vals)
    Salesforce.push_data_to_salesforce("Contact",data,auth_vals)
  end

  def self.campaignmembers_to_salesforce(data,auth_vals)
    Salesforce.push_data_to_salesforce("CampaignMember",data,auth_vals)
  end

  # initiate API authentication and return hash of auth values
  def self.get_rest_authentication()
    # URLs
    sf_oauth_prefix = ENV['sf_oauth_prefix']
    oauth_token_endpoint = "#{sf_oauth_prefix}/services/oauth2/token"

    # Auth
    client_id = ENV['sf_client_id']
    client_secret = ENV['sf_client_secret']
    username = ENV['sf_username']
    password = ENV['sf_password']
    auth_payload = "grant_type=password&client_id=#{client_id}" \
      "&client_secret=#{client_secret}" \
      "&username=#{username}&password=#{password}"
    params = {:accept => 'application/json'}
    auth_response = REST.authenticate_salesforce(oauth_token_endpoint,auth_payload,params)
    auth_json = JSON.parse(auth_response)
    auth_vals = {"access_token" => auth_json["access_token"],
      "instance_url" => auth_json["instance_url"]}
  end

  # search salesforce for Eventbrite data
  def self.search_salesforce(object_type,obj,instance_url,access_token)
    search_string = Searcher.new.search(object_type,obj)
    search_string = Formatter.url_encode(search_string)
    base_uri = "#{instance_url}/services/data/v29.0/query/?q=#{search_string}"
    puts base_uri
    query_response = REST.get(base_uri,access_token)
  end

  # test method for experimenting with Salesforce & Eventbrite REST API Calls
  def self.push_data_to_salesforce(object_type,data,auth_vals)
    instance_url = auth_vals["instance_url"]
    access_token = auth_vals["access_token"]
    data[0].each do |obj|
      obj = add_ids_to_campaignmember(obj,instance_url,access_token) if object_type == "CampaignMember"
      next if obj.nil?
      json_payload = Salesforce.get_json_payload(object_type,obj)
      query_response = Salesforce.search_salesforce(object_type,obj,instance_url,access_token)
      puts query_response
      # rest api call parameters
      unless query_response == '{"totalSize":0,"done":true,"records":[]}'
        if object_type == "CampaignMember"
          json_payload = Salesforce.get_json_payload("CampaignMemberPatch",obj)
          json_response = JSON.parse(query_response)
          response_id = json_response["records"][0]["Id"]
          base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/#{response_id}"
          puts REST.patch(base_uri,json_payload,access_token)
        else
          json_response = JSON.parse(query_response)
          response_id = json_response["records"][0]["Id"]
          base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/#{response_id}"
          # prevent events from getting patched
          chapter = JSON.parse(json_payload)["Chapter__c"] if object_type == "Campaign"
          unless chapter == ENV['bad_chap']
            puts REST.patch(base_uri,json_payload,access_token)
          end
        end
      else
        base_uri = "#{instance_url}/services/data/v29.0/sobjects/#{object_type}/"
        puts REST.post(base_uri,json_payload,access_token)
      end
    end
  end

  # potential method for handling some of the start-up functions in each of the
  # x_to_salesforce methods
  def self.get_json_payload(object_type, obj)
    csv = DataWriter.get_sobject_fields(object_type, obj)
    payload = DataWriter.build_payload_from_csv(csv,obj)
    # Short-term solution to excessive titles and incorrect titles
    if object_type == "Campaign"
      payload["Name"] = payload["Name"][0..79] if payload["Name"].length > 80
    elsif object_type == "Contact"
      payload["Email"] = obj["order"]["email"] if obj["profile"]["email"].nil?
      payload["Email"] = payload["Email"].gsub(',','')
    end
    json_payload = JSON.generate(payload)
  end

  def self.get_sobject_fields(object_type, obj)
    case
    when object_type == "Campaign"
      @csv = CSV.read('data/campaign_fields.csv')
    when object_type == "Contact"
      @csv = CSV.read('data/contact_fields.csv')
    when object_type == "CampaignMember"
      @csv = CSV.read('data/campaignmember_fields.csv')
    when object_type == "CampaignMemberPatch"
      @csv = CSV.read("data/campaignmemberpatch_fields.csv")
    end
    return @csv
  end

  # adds Campaign and Contact Id info to CampaignMember payload before processing
  def self.add_ids_to_campaignmember(obj, instance_url, access_token)
    json_payload = nil
    campaign_id = obj["event"]["id"]
    contact_fn = Formatter.escape_characters(obj["profile"]["first_name"])
    contact_ln = Formatter.escape_characters(obj["profile"]["last_name"])
    contact_email = obj["profile"]["email"]
    contact_email = obj["order"]["email"] if contact_email.nil?
    contact_email = Formatter.escape_characters(contact_email)
    checked_in = nil
    checked_in = "Responded" if obj["checked_in"]
    campaign_search_string =
      Formatter.url_encode(
        "SELECT Id" \
        " FROM Campaign" \
        " WHERE External_ID__c = '#{campaign_id}'")
    contact_search_string =
      Formatter.url_encode(
      "SELECT Id" \
      " FROM Contact" \
      " WHERE FirstName = '#{contact_fn}'" \
      " AND LastName = '#{contact_ln}'" \
      " AND (npe01__HomeEmail__c = '#{contact_email}'" \
      " OR npe01__AlternateEmail__c = '#{contact_email}')")
    campaign_base_uri = "#{instance_url}/services/data/v29.0/query/?q=#{campaign_search_string}"
    puts campaign_base_uri
    campaign_query_response = REST.get(campaign_base_uri,access_token)
    puts "add_ids campaign_query_response = #{campaign_query_response}"
    json_campaign = JSON.parse(campaign_query_response)
    puts json_campaign["records"][0]["Id"]
    contact_base_uri = "#{instance_url}/services/data/v29.0/query/?q=#{contact_search_string}"
    contact_query_response = REST.get(contact_base_uri,access_token)
    json_contact = JSON.parse(contact_query_response)
    puts json_contact["records"][0]["Id"]
    unless json_contact.nil?
      obj.store("ContactId",json_contact["records"][0]["Id"])
      obj.store("CampaignId",json_campaign["records"][0]["Id"])
      obj.store("Status",checked_in) unless checked_in.nil?
    else
      obj = nil
    end
    return obj
  end
end
