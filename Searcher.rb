require 'rubygems'
require 'bundler/setup'
require './Formatter.rb'

class Searcher

  def search(object_type,obj)
      if object_type == "Campaign"
        return campaign(obj)
      elsif object_type == "Contact"
        return contact(obj)
      elsif object_type == "CampaignMember"
        return campaignmember(obj)
      end
  end

  def campaign(obj)
    campaign_id = obj["id"]
    search_string =
        "FIND {#{campaign_id}}" \
        " IN ALL FIELDS" \
        " RETURNING Campaign(Id)"
  end

  def contact(obj)
    contact_fn = obj["profile"]["first_name"]
    contact_ln = obj["profile"]["last_name"]
    contact_email = obj["profile"]["email"]
    contact_email = obj["order"]["email"] if contact_email.nil?
    [contact_fn,contact_ln,contact_email].each do |field|
      field = Formatter.escape_characters(field)
    end
    search_string =
        "FIND {\"#{contact_fn}" \
        " #{contact_ln}\"" \
        " AND #{contact_email}}" \
        " IN ALL FIELDS" \
        " RETURNING Contact(Id)"
  end

  def campaignmember(obj)
    contact_id = obj["ContactId"]
    campaign_id = obj["CampaignId"]
    search_string =
        "SELECT Id" \
        " FROM CampaignMember" \
        " WHERE CampaignId='#{campaign_id}'" \
        " AND ContactId='#{contact_id}'"
  end
end
