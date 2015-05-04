require 'rubygems'
require 'bundler/setup'
require 'rest-client'

module REST

    def REST.get_params(access_token)
      params =
        {"Authorization" => "Bearer #{access_token}",
        :content_type => 'application/json',
        :accept => 'application/json',
        :verify => false}
     end

    # method for handling HTTP-GET calls
    def REST.get(base_uri,access_token)
      params = REST.get_params(access_token)
      begin
        @response = RestClient.get(base_uri,params)
      rescue => e
        puts @response.code
      end
      return @response
    end

    # method for handling HTTP-POST calls
    def REST.post(base_uri,json_payload,access_token)
      params = REST.get_params(access_token)
      begin
        @response = RestClient.post(base_uri,json_payload,params)
      rescue => e
        puts @response.code
      end
      return @response
    end

    # method for handling HTTP-PATCH calls
    def REST.patch(base_uri,json_payload,access_token)
      params = REST.get_params(access_token)
      begin
        @response = RestClient.patch(base_uri,json_payload,params)
      rescue => e
        puts @response.code
      end
      return @response
    end

    def REST.authenticate_salesforce(base_uri,json_payload,params)
      begin
        @response = RestClient.post(base_uri,json_payload,params)
      rescue => e
        puts @response.code
      end
      return @response
    end
end
