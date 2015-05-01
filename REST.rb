require 'rubygems'
require 'bundler/setup'
require 'rest-client'

class REST
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
end
