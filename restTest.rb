# EvenUp REST callback test handler
#
# To run: thin -R config.ru -D -p 2345 start
#
# Input and results are logged to the console and returned to the client
#
# gems required: thin sinatra awesome_print json hash_validator
#
require 'rubygems'
require 'sinatra'


class RestTest < Sinatra::Application
  require 'awesome_print'
  require 'json'
  require 'hash_validator'

  helpers do
    def protected!
      return if authorized?
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Authentication failed"
    end

    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == ['user', 'password']
    end

    def processMessage request
      begin
        data = request.env["rack.input"].read
        received = JSON.parse(data)
        puts "Received:"
        ap received
      rescue
        puts "Invalid JSON received: #{data}"
        halt 400, 'Invalid JSON'
      end

      case received['type']
      when 'ACCOUNT_CREATED'
        validate!(received, :account_created)
      when 'ACCOUNT_DEACTIVATED'
        validate!(received, :account_deactivated)
      when 'EVENT_VIEWED'
        validate!(received, :event_viewed)
      when 'EVENT'
        eventTypes = ['MCD_GENERATED', 'VOICEMAIL', 'CALL_CAPTURE', 'TEMPLATE']
        if !eventTypes.include? received['eventType']
          halt 400, "Invalid eventType #{received['eventType']}"
        end
        validate!(received, ("event_#{received['eventType'].downcase}").to_sym)
      else
        halt 400, "Unknown type: #{received['type']}"
      end
      puts "#{received['type']} validated"
      "#{received['type']} validated"
    end

    def validate!(received, validator)
      validations = {
        :account_created => {
          'accountGuid'   => 'string',
          'accountNumber' => 'string',
          'firstName'     => 'string',
          'lastName'      => 'string',
          'acn'           => 'string',
          'acnExtension'  => 'string',
          'acnPass'       => 'string',
          'eventTime'     => lambda { |t| Time.iso8601(t) }
        },
        :account_deactivated => {
          'accountGuid'   => 'string',
          'accountNumber' => 'string',
          'firstName'     => 'string',
          'lastName'      => 'string',
          'eventTime'     => lambda { |t| Time.iso8601(t) }
        },
        :event_viewed => {
          'accountGuid' => 'string',
          'eventGuid'   => 'string',
          'eventTime'   => lambda { |t| Time.iso8601(t) }
        },
        :event_mcd_generated => {
          'accountGuid' => 'string',
          'eventGuid'   => 'string',
          'eventTime'   => lambda { |t| Time.iso8601(t) },
          'mcdUrl'      => 'string'
        },
        :event_voicemail  => {
          'accountGuid'   => 'string',
          'eventGuid'     => 'string',
          'eventTime'     => lambda { |t| Time.iso8601(t) },
          'voicemailUrl'  => 'string'
        },
        :event_call_capture  => {
          'accountGuid'   => 'string',
          'eventGuid'     => 'string',
          'eventTime'     => lambda { |t| Time.iso8601(t) },
          'recordingUrl'  => 'string'
        },
        :event_template => {
          'accountGuid'   => 'string',
          'eventGuid'     => 'string',
          'eventTime'     => lambda { |t| Time.iso8601(t) },
          'templateId'    => 'string',
          'values'        => lambda { |v| v.is_a?(Hash) && v.length > 0 }
        }
      }

      if !validations.has_key?(validator)
        halt 500, "Validator not present for #{validator}"
      end

      validator = HashValidator.validate(received, validations[validator])
      if !validator.valid?
        ap validator.errors
        halt 400, validator.errors
      end

    end
  end

  post '/' do
    processMessage request
  end

  post '/httpauth' do
    protected!
    processMessage request
  end
end
