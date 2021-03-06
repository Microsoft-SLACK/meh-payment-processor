require 'sinatra/base'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'dm-observer'
require 'dm-types'
require 'haml'
require 'extlib_lite'
require './app/models/payment_request'
require './app/models/payment_request_observer'
require './app/models/remote_payment_request'
require './app/models/paypal_payment_request'
require './app/models/payee'
require './app/helpers/application_helper'

class MehPaymentProcessor < Sinatra::Base

  set app_settings = YAML.load(
    File.read("config/#{environment.to_s}.yml")
  )

  set :views, File.dirname(__FILE__) + '/app/views'
  set :method_override, true   # enables put and delete requests for forms
  enable :sessions

  helpers do
    include ApplicationHelper
  end

  before do
    request_method = request.env["REQUEST_METHOD"]
    if request_method == "POST" || request_method == "PUT" || request_method == "DELETE"
      protect_from_forgery(params) unless
        skip_forgery_protection?(request.env["PATH_INFO"])
    end
  end

  set :skip_forgery_protection, [ "/payment_requests", /^\/tasks\/.+$/ ]

  get '/tasks/ping' do
    200
  end

  put '/tasks/verify/payment_requests/:id' do
    payment_request = PaymentRequest.get(params["id"])
    remote_payment_request = RemotePaymentRequest.new(
      app_settings['remote_application']['uri']
    )
    remote_payment_request.verify(payment_request)
  end

  put '/tasks/process/payment_requests/:id' do
    payment_request = PaymentRequest.get(params["id"])
    if payment_request.authorized? && !payment_request.sent_for_processing?
      payment_request.send_for_processing
      paypal_payment_request = PaypalPaymentRequest.new(
        app_settings['paypal']['api_credentials']
      )
      response = paypal_payment_request.pay(
        app_settings['paypal']['uri'],
        app_settings['my_application']['uri'],
        app_settings['my_application']['uri'],
        payment_request.payment_params
      )
      payment_request.complete(response)
    end
  end

  put '/tasks/remote_payment_requests/:id' do
    payment_request = PaymentRequest.get(params["id"])
    RemotePaymentRequest.new(
      app_settings['remote_application']['uri']
    ).notify(payment_request)
  end

  get '/cron/ping' do
    5.times do |i|
      AppEngine::Labs::TaskQueue.add(
        nil,
        :url => "/tasks/ping",
        :method => 'GET',
        :countdown => (i + 1) * 10
      )
    end
  end

  post '/payment_requests' do
    PaymentRequest.create(params["payment_request"])
  end

  head '/payment_requests/:id' do
    payment_request = PaymentRequest.get(params["id"])
    if payment_request && payment_request.notification_sent?
      merged_params = params.merge(payment_request.notification)
      merged_params == params ? 200 : 404
    else
      404
    end
  end

  get '/' do
    redirect :'admin/payees'
  end

  # Payee Resource

  # index
  get '/admin/payees' do
    @payees = Payee.all
    haml :'admin/payees/index'
  end

  # new
  get '/admin/payees/new' do
    @payee = Payee.new
    haml :'admin/payees/new'
  end

  # edit
  get '/admin/payees/:id/edit' do
    if @payee = Payee.get(params["id"])
      haml :'admin/payees/edit'
    else
      redirect '/admin/payees'
    end
  end

  # create
  post '/admin/payees' do
    @payee = Payee.new(params["payee"])
    if @payee.save
      redirect '/admin/payees'
    else
      haml :'admin/payees/new'
    end
  end

  # update
  put '/admin/payees/:id' do
    @payee = Payee.get(params["id"])
    if @payee.update(params["payee"])
      redirect '/admin/payees'
    else
      haml :'admin/payees/edit'
    end
  end

  # destroy
  delete '/admin/payees/:id' do
    Payee.get(params["id"]).destroy!
    redirect '/admin/payees'
  end

  # show (delete with javascript disabled)
  get '/admin/payees/:id' do
    if @payee = Payee.get(params["id"])
      haml :'admin/payees/show'
    else
      redirect '/admin/payees'
    end
  end
end

