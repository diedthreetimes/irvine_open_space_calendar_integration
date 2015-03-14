#!/usr/bin/env ruby

#require 'sqlite3'
require 'google/api_client'
require 'google/api_client/auth/file_storage'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'pry'

# General TODOs
# 1. Keep track of already seen events in a sqlite db and query them again.
# 2. Periodically run (cron is fine) to keep calendar synched (depends mostly on 1)

BASE_DIR = File.dirname(__FILE__)

# Google API Params
# TODO make sure the following to files start form current directory
SECRET_FILE = "#{BASE_DIR}/secrets/google_api.yaml"
CREDENTIAL_STORAGE_FILE = "#{BASE_DIR}/secrets/oauth2.json"
AUTH_SCOPE = ['https://www.googleapis.com/auth/calendar']


# Scrape params
BASE_URL = "http://letsgooutside.org/activities/?action=search_events&pno="
SCRAPE_LIMIT = 1 # TODO: Parse the nav at the bottom and crawl all pages
DEBUG_PARSE = true
TEST_PAGE = "#{BASE_DIR}/sample/access_example.html"

class Event
  attr_accessor :start_time
  attr_accessor :stop_time
  attr_accessor :description
  attr_accessor :title
  attr_accessor :location
  attr_accessor :more_details
  attr_accessor :all_day_event

  def parse_start_stop date_str, time_str
    return self if date_str.nil?

    date_str.slice!(/.*, /) # Revome day of the week: Mon, Tue, etc.
    date = Date.strptime(date_str, "%m/%d/%Y")

    if time_str.nil?
      all_day_event = true

      start_time = date.to_time
      stop_time = date.to_time
    else

      split = time_str.split('-')

      # TODO: Fix the PST time, for now IDC I'm always in PST :P
      start = Time.parse(split[0])
      stop = Time.parse(split[1])

      # Combine date and time
      self.start_time = Time.new( date.year, date.month, date.day, start.hour, start.min, start.sec )
      self.stop_time = Time.new( date.year, date.month, date.day, stop.hour, stop.min, stop.sec )

      puts start_time
      puts stop_time
    end

    self
  end

  def to_s
    puts "T: #{title}"
    puts "D: #{description.slice(0,70)}"
    puts "L: #{location}"
    puts "H: #{more_details}"
    puts "S: #{start_time.to_s}"
    puts "E: #{stop_time}"
    puts "--------------------"
  end
end


def google_tokens
  $tokens ||= YAML.load_file(SECRET_FILE)
end

def client
  $client ||= Google::APIClient::InstalledAppFlow.new(
                       :client_id => google_tokens[:oauth][:client_id],
                       :client_secret => google_tokens[:oauth][:client_secret],
                       :scope => [AUTH_SCOPE]
                                                    )

  authorize if $client.authorization.access_token.nil?

  $client
end

def authorize
  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  if file_storage.authorization.nil?
    client.authorization = flow.authorize(file_storage)
  else
    client.authorization = file_storage.authorization
  end
end

def calendar
  $calapi= client.discovered_api('TODO')
end

def make_calendar

end

def make_event event
  return if event_present?( event )

  puts event.to_s
end

def event_present? event
  false
end

def parse_page html
  page = Nokogiri::HTML(html)

  page.css(".event-listing").each do |event_e|
    event = Event.new

    event.description = event_e.css('.event-description p').text
    event.title = event_e.css('.event-header .event-title a').text
    event.more_details = event_e.css('.event-header .event-title a').first['href']

    date = nil
    time = nil
    event_e.css('.event-meta dl').children.each_slice(2) do |term_e, value_e|
      if term_e.text =~ /Where/
        event.location = value_e.text
      elsif term_e.text =~ /Date/
        date = value_e.text
      elsif term_e.text =~ /Time/
        time = value_e.text
      end
    end

    event.parse_start_stop( date, time )

    make_event event
  end
end

def scrape_all
  if DEBUG_PARSE
    parse_page File.open(TEST_PAGE)
    return
  end
  SCRAPE_LIMIT.times do |i|
    uri = URI.parse(BASE_URL + i)

    parse_page( Net::HTTP.get_response(uri).body )
  end
end


if __FILE__ == $0
  make_calendar

  scrape_all
end
