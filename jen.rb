#!/usr/bin/env ruby

# Alexa RubyEngine
# This Engine receives and responds to Amazon Echo's (Alexa) JSON requests.
require 'sinatra'
require 'sinatra/base'
require 'json'
require 'bundler/setup'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'alexa_rubykit'
require 'date'
require 'net/http'
require 'uri'
require 'open-uri'
require 'yaml/store'
require 'humanize'

def encodeURIcomponent str
  return URI.escape(str, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
end


def make_org_entry heading, context, priority, date, body
#  $logger.debug "TODO [#{priority}] #{heading} #{context}"
#  $logger.debug "SCHEDULED: #{date}"
#  $logger.debug "#{body}"
  title = encodeURIcomponent "[#{priority}] #{heading}  :#{context}:"
  body  = encodeURIcomponent "SCHEDULED: #{date}\n#{body}"
  uri = URI.parse("http://carbon:3333")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new("/capture/b/LINK/#{title}/#{body}")
  response = http.request(request)
  return response
end

module AlexaRubykit
  class Response
    def add_ssml(speech_text)
      @speech = { :type => 'SSML', :ssml => speech_text }
      @speech
    end
  end
end


class Float
  def fuzz unit
    int = itself.to_int
    frac = ((itself - int) * 100).to_int
    prefix = case frac %25
             when 0..3
               "about"
             when 4..12
               "a little more than"
             when 13..22
               "a little less than"
             when 22..24
               "about"
             end
    quadrant = case frac
               when 0..12
                 nil
               when 13..12+25
                 'a quarter'
               when 13+25..12+50
                 'a half'
               when 13+50..12+75
                 'three quarters'
               when 13+75..99
                 int += 1
                 nil
               end
    composite = prefix
    composite += " " + int.humanize.strip if quadrant.nil? || int != 0
    quadrant = "and " + quadrant unless quadrant.nil? || int == 0
    composite = [composite, quadrant, unit].compact.join(' ')
    composite += 's' unless int == 1 && composite.match(/one\s*$/) || int == 0 && !quadrant.nil?
    return composite
  end
end


class MyServer < Sinatra::Base
  # We must return application/json as our content type.
  before do
    content_type('application/json')
  end

  #enable :sessions
  post '/' do
    # Check that it's a valid Alexa request
    request_json = JSON.parse(request.body.read.to_s)
    # Creates a new Request object with the request parameter.
    request = AlexaRubykit.build_request(request_json)

    # We can capture Session details inside of request.
    # See session object for more information.
    session = request.session
    p "--------------------------------------------------"
    # p "new?            #{session.new?}"
    # p "has_attributes? #{session.has_attributes?}"
    # p "session_id      #{session.session_id}"
    # p "user_defined    #{session.user_defined?}"
    # p "user            #{session.user}"
    # We need a response object to respond to the Alexa.
    response = AlexaRubykit::Response.new

    # We can manipulate the request object.
    #
    p "#{request.to_s}"
    #p "#{request.request_id}"

    end_session = true

    # Response
    # If it's a launch request
    case request.type
    when 'LAUNCH_REQUEST'
      # Process your Launch Request
      # Call your methods for your application here that process your Launch Request.
      # p "type: #{request.type}"
      response.add_speech("Jen is listening")
      response.add_hash_card( { :title => 'Ruby Run', :subtitle => 'Jen is listening!' } )
      end_session = false

    when 'INTENT_REQUEST'
      speech = []

      case request.name
      when 'HelpIntent'
        speech.unshift "You can ask me to remember something, or you can ask what are my jobs, or how much power are the solar panels producing."

      when 'TaskIntent'
        date = Time.now
        if not request.slots['Date']['value'].nil?
          begin
            date = Date.parse(request.slots['Date']['value'])
          rescue
            date = Time.now
            speech.unshift "I didn't quite catch the date, so I put it down for today."
          end
        end

        org_response = make_org_entry request.slots['Message']['value'], '@home', '#C',
                                  "<#{date.strftime('%F %a')}>", ""
        if (org_response.code == '200')
          speech.unshift "Sure, I'll remember to #{request.slots['Message']['value']} on #{date.strftime('%A')} <say-as interpret-as='date'>????#{date.strftime('%m%d')}</say-as>."
        else
          speech.unshift "Sorry, make org entry responded with #{org_response.code} #{org_response.message}."
        end

      when 'JobsIntent'
        buffer = open("http://carbon:3333/agenda/day").read
        #puts buffer
        buffer.scan(/<span class="org-scheduled.*?"> \[#.\] (.*?)<\/span>/) { |job| speech.unshift "<p>#{job[0]}</p>"}

      when 'SolarIntent'
        begin
          sunpower_credentials = YAML.load_file File.join(Dir.home, '.credentials', "sunpower.yaml")
          api_base_url = "https://monitor.us.sunpower.com/CustomerPortal/"

          uri = URI.parse(api_base_url + "Auth/Auth.svc/Authenticate")
          http = Net::HTTP.new uri.hostname, uri.port
          http.use_ssl = true
          auth_response = http.send_request 'POST', uri.path, sunpower_credentials.to_json, {'Content-Type' => 'application/json'}
          decoded = JSON.parse(auth_response.body)

          current_power_response = open(api_base_url + "CurrentPower/CurrentPower.svc/GetCurrentPower?id=#{decoded['Payload']['TokenID']}").read
          puts current_power_response
          decoded = JSON.parse current_power_response

          production = decoded['Payload']['CurrentProduction'].to_f
          if production > 0
            if production < 1.0
              speech.unshift "The panels are producing #{(production*1000).fuzz('watt')}."
            else
              speech.unshift "The panels are producing #{production.fuzz('kilowatt')}."
            end
          else
            speech.unshift "The panels aren't producing right now."
          end
        rescue Exception => e
          speech.unshift "There was a problem accessing sunpower.  The exception was #{e}"
        end
        #puts buffer
      end

      response.add_ssml('<speak>' + speech.join(' ') + '</speak>')
      response.add_hash_card( { :title => 'Ruby Intent', :subtitle => "Intent #{request.name}" } )

    when 'SESSION_ENDED_REQUEST'
      # Wrap up whatever we need to do.
      # p "type:   #{request.type}"
      # p "reason: #{request.reason}"
      halt 200
    end

    response.build_response end_session
  end
end


CERT_PATH = './'

webrick_options = {
  :Host               => '192.168.1.147',
  :Port               => 8443,
  :Logger             => WEBrick::Log::new($stderr, WEBrick::Log::DEBUG),
  :DocumentRoot       => "/ruby/htdocs",
  :SSLEnable          => true,
  :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
  :SSLCertificate     => OpenSSL::X509::Certificate.new(  File.open(File.join(CERT_PATH, "server.crt")).read),
  :SSLPrivateKey      => OpenSSL::PKey::RSA.new(          File.open(File.join(CERT_PATH, "privatekey.pem")).read),
  :app                => MyServer
}

Rack::Server.start webrick_options
