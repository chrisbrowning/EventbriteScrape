require 'rubygems'
require 'bundler/setup'
require 'rest-client'

module REST

    def self.get_params(access_token)
      params =
        {"Authorization" => "Bearer #{access_token}",
        :content_type => 'application/json',
        :accept => 'application/json',
        :verify => false}
     end

    # method for handling HTTP-GET calls
    def self.get(base_uri,access_token)
      params = REST.get_params(access_token)
      begin
        puts base_uri
        @response = RestClient.get(base_uri,params)
      rescue => e
        puts @response.code
      end
      return @response
    end

    # method for handling HTTP-POST calls
    def self.post(base_uri,json_payload,access_token)
      params = REST.get_params(access_token)
      begin
        @response = RestClient.post(base_uri,json_payload,params)
      rescue => e
        puts @response.code
      end
      return @response
    end

    # method for handling HTTP-PATCH calls
    def self.patch(base_uri,json_payload,access_token)
      params = REST.get_params(access_token)
      begin
        @response = RestClient.patch(base_uri,json_payload,params)
        puts "PATCH RESPONSE = #{@response}"
      rescue => e
        puts @response.code
      end
      return @response
    end

    def self.authenticate_salesforce(base_uri,json_payload,params)
        return RestClient.post(base_uri,json_payload,params)
    end
end
