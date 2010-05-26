class PaymentRequest
  include DataMapper::Resource
  property :id, Serial
  property :email, String, :format => :email_address, :required => true
  property :params, Yaml
  timestamps :at
end
