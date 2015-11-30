#!/usr/bin/ruby

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

    # Response
    # If it's a launch request
    if (request.type == 'LAUNCH_REQUEST')
      # Process your Launch Request
      # Call your methods for your application here that process your Launch Request.
      # p "type: #{request.type}"
      response.add_speech("Jen is listening")
      response.add_hash_card( { :title => 'Ruby Run', :subtitle => 'Jen is listening!' } )
    end

    if (request.type == 'INTENT_REQUEST')
      speech = []
      if (request.name == 'TaskIntent')
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
      elsif (request.name == 'JobsIntent')
        buffer = open("http://carbon:3333/agenda/day").read
        puts buffer
        buffer.scan(/<span class="org-scheduled.*?"> \[#.\] (.*?)<\/span>/) { |job| speech.unshift "<p>#{job[0]}</p>"}
      end
      response.add_ssml('<speak>' + speech.join(' ') + '</speak>')
      response.add_hash_card( { :title => 'Ruby Intent', :subtitle => "Intent #{request.name}" } )
    end

    if (request.type =='SESSION_ENDED_REQUEST')
      # Wrap up whatever we need to do.
      # p "type:   #{request.type}"
      # p "reason: #{request.reason}"
      halt 200
    end

    # Return response
    response.build_response
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
