require 'rubygems'
require 'bundler/setup'
require './Formatter.rb/escape_characters'

class Searcher

  def search(object_type,obj)
    case object_type
    when "Campaign"
      @search_string = campaign(obj)
    when "Contact"
      @search_string = contact(obj)
    when "CampaignMember"
      @search_string = campaignmember(obj)
      type = "query"
    end
    puts @search_string
    return @search_string
  end

  def campaign(obj)
    campaign_id = obj["id"]
    search_string =
        "FIND {#{campaign_id}}" \
        " IN ALL FIELDS" \
        " RETURNING Campaign(Id)"
  end

  def contact
    contact_fn = escape_characters(obj["profile"]["first_name"])
    contact_ln = escape_characters(obj["profile"]["last_name"])
    contact_email =  obj["profile"]["email"]
    contact_email = obj["order"]["email"] if contact_email.nil?
    contact_email = Formatter.new.escape_characters(contact_email)
    search_string =
        "FIND {\"#{contact_fn}" \
        " #{contact_ln}\"" \
        " AND #{contact_email}}" \
        " IN ALL FIELDS" \
        " RETURNING Contact(Id)"
  end

  def campaignmember
    contact_id = obj["ContactId"]
    campaign_id = obj["CampaignId"]
    type = "query"
    search_string =
        "SELECT Id" \
        " FROM CampaignMember" \
        " WHERE CampaignId='#{campaign_id}'" \
        " AND ContactId='#{contact_id}'"
  end
end
