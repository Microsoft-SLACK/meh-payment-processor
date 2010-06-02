require 'sinatra/base'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'dm-observer'
require 'dm-types'
require './lib/dm_extlib_hash'
require './app/models/payment_request'
require './app/models/supplier'
require './app/models/payment_request_observer'

class MehPaymentProcessor < Sinatra::Base

  set app_settings = YAML.load(
    File.read('config/app_settings.yml')
  )[environment.to_s]

  # All uri's starting with /task are private for the
  # task queue. NOTE: never use create! with DM because
  # it will bypass hooks and the observer will not be run
  post '/tasks/payment_requests/create' do
    PaymentRequest.create(:to => params["to"], :params => params)
  end
  
  post '/tasks/requester_application/payment_requests/show' do
    # because the TaskQueue doesn't support hashes of hashes we passed
    # entire hash as as string. And we use eval to get it back to a hash of hashes
    parsed_params = eval(params["params"])
    #payment_request = PaymentRequest.get(parsed_params["id"])
    puts URI.join(
      app_settings['requester_application_uri'],
      'payment_requests/show'
    ).to_s << '?' << parsed_params["params"].to_params
    response = AppEngine::URLFetch.fetch(
      URI.join(
        app_settings['requester_application_uri'],
        'payment_requests/show'
      ).to_s
    )
    puts response.inspect
  end

  # External request is executed here
  # We just delegate the work to /tasks/payment_requests/create
  # for a later time to ensure a fast response time
  post '/payment_requests/create' do
    # Schedule the creation of a payment request to the queue
    AppEngine::Labs::TaskQueue.add(
      nil,
      :params => params,
      :url => '/tasks/payment_requests/create'
    )
  end
  
end
