#!/usr/bin/env ruby

#require 'sqlite3'
require 'google/api_client'
require 'google/api_client/auth/file_storage'
require 'google/api_client/auth/installed_app'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'yaml'
require 'time'
require 'pry'


# General TODOs
# 1. Keep track of already seen events in a sqlite db and query them again.
# 2. Periodically run (cron is fine) to keep calendar synched (depends mostly on 1)

BASE_DIR = File.dirname(__FILE__)

# Google API Params
SECRET_FILE = "#{BASE_DIR}/secrets/google_api.yaml"
CREDENTIAL_STORE_FILE = "#{BASE_DIR}/secrets/oauth2.json"
AUTH_SCOPE = ['https://www.googleapis.com/auth/calendar']
SAVED_CALENDAR = "#{BASE_DIR}/secrets/saved_calendar.yaml"
HIGHLIGHT_COLOR = "7"
HIGHLIGHT_FILTER = /Wilderness Access/

# Scrape params
BASE_URL = "http://letsgooutside.org/activities/?action=search_events&pno="
SCRAPE_LIMIT = 10
DEBUG_PARSE = false
TEST_PAGE = "#{BASE_DIR}/sample/access_example.html"

class Event
  attr_accessor :start_time
  attr_accessor :stop_time
  attr_accessor :description
  attr_accessor :title
  attr_accessor :location
  attr_accessor :more_details
  attr_accessor :all_day

  def parse_start_stop date_str, time_str
    return self if date_str.nil?

    date_str.slice!(/.*, /) # Revome day of the week: Mon, Tue, etc.
    date = Date.strptime(date_str, "%m/%d/%Y")

    if time_str.nil?
      all_day = true

      self.start_time = date.to_time
      self.stop_time = date.to_time
    else

      split = time_str.split('-')

      # TODO: Fix the PST time, for now IDC I'm always in PST :P
      start = Time.parse(split[0])
      stop = Time.parse(split[1])

      # Combine date and time
      self.start_time = Time.new( date.year, date.month, date.day, start.hour, start.min, start.sec )
      self.stop_time = Time.new( date.year, date.month, date.day, stop.hour, stop.min, stop.sec )
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

  def query_title
    # Remove special characters
    title.gsub("-"," ").gsub(":"," ")
  end

  def to_hash
    start_hash = if all_day then
      {'date' => start_time.rfc3339} # formatted as yyyy-mm-dd
    else
      {'dateTime' => start_time.rfc3339} # formatted as # RFC 3339 wtih a timezone offset (or 'timezone' field)
    end

    stop_hash = if all_day then
      {'date' => stop_time.rfc3339} # formatted as yyyy-mm-dd
    else
      {'dateTime' => stop_time.rfc3339} # formatted as # RFC 3339 wtih a timezone offset (or 'timezone' field)
    end


    {
      'summary' => title,
      'description' => description,
      'location' => location,
      'start' => start_hash,
      'end' => stop_hash,
      'source' => {
        'title' => title,
        'url' => more_details
      }
    }
  end

  def to_json color = nil
    hash = to_hash
    if color
      hash["colorId"] = color
    end

    JSON.dump(hash)
  end
end

class Time
  def rfc3339 i = 0
    to_datetime.rfc3339(i)
  end
end

def say msg
  puts msg
end

def google_tokens
  $tokens ||= YAML.load_file(SECRET_FILE)
end

def client
  $client ||= Google::APIClient.new(
     :application_name => "IrvineOpenSpaceImporter",
     :application_version => "1.0.0")

  authorize if ($client.authorization.nil? || $client.authorization.access_token.nil?)

  $client
end

def authorize
  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  if file_storage.authorization.nil?
    flow = Google::APIClient::InstalledAppFlow.new(
                       :client_id => google_tokens["oauth"]["client_id"],
                       :client_secret => google_tokens["oauth"]["client_secret"],
                       :scope => [AUTH_SCOPE])

    $client.authorization = flow.authorize(file_storage)
  else
    $client.authorization = file_storage.authorization
  end
end

def calendar
  $calapi= client.discovered_api('calendar', 'v3')
end

def calendar_exists? id
  result = client.execute(:api_method => calendar.calendars.get,
                          :parameters => {'calendarId' => id})

  if !result.data?
    false
  elsif result.data && result.data["error"]
    if result.data["error"]["errors"].first["reason"] == "notFound"
      false
    else
      abort("Calendar could not be verified " + result.data["error"]["errors"].first["reason"].to_s)
    end
  else
    true
  end
end

def make_calendar summary = 'Open Space Preserve'
  result = client.execute(:api_method => calendar.calendars.insert,
                          :body => {'summary' => summary}.to_json,
                          :headers => {'Content-Type' => 'application/json'})

  return nil if !result.data?

  # TODO: Why does the summary not get send with the boyd?
  if !result.data["error"].nil?
    abort result.data["error"]["message"]
  end

  id = result.data["id"]
  File.open( SAVED_CALENDAR, 'w' ) {|file|
    file.write(id)
  }

  id
end

def make_event event, calendar_id
  if event_present?( event, calendar_id )
    say "#{event.title} already on the calendar"
    return # TODO: Eventually silence this statmenet
  end


  color = if event.title =~ HIGHLIGHT_FILTER
            HIGHLIGHT_COLOR
          else
            nil
          end

  result = client.execute(:api_method => calendar.events.insert,
                          :parameters => { 'calendarId' => calendar_id},
                          :body => event.to_json(color),
                          :headers => {'Content-Type' => 'application/json'})
  if !result.data?
    warn "#{event.title} could not be saved"
  end

  # TODO: Save the resulting event id (result.data.id)
end

def event_present? event, calendar_id
  result = client.execute(:api_method => calendar.events.list,
                          # These times need to be datetimes, the library may not handle times correctly
                          :parameters => {'timeMin' => event.start_time.rfc3339, 'timeMax' => event.stop_time.rfc3339,
                            'q' => event.query_title, 'singleEvents' => "true", 'calendarId' => calendar_id})

  if !result.data?
    false
  elsif result.data["error"]
    # TODO: raise instead
    abort result.data["error"]["message"]
  end

  !result.data["items"].empty?
end

def parse_page html, calendar_id
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

    make_event( event, calendar_id )
  end
end

def scrape_all calendar_id
  if DEBUG_PARSE
    parse_page( File.open(TEST_PAGE), calendar_id )
    return
  end

  # TODO: Parse the nav at the bottom and crawl all pages
  SCRAPE_LIMIT.times do |i|
    uri = URI.parse(BASE_URL + (i+1).to_s)

    puts "Fetching #{BASE_URL}#{i+1}"

    parse_page( Net::HTTP.get_response(uri).body, calendar_id )
  end
end


if __FILE__ == $0
  id = nil
  if !File.exists?( SAVED_CALENDAR )
    say "No saved calendar, creating a new one"
    id = make_calendar
  else
    id = File.open( SAVED_CALENDAR ).readline.strip
    unless calendar_exists? id
      say "Calendar for #{id} not found, making a new one"
      id = make_calendar
    end
  end

  if id.nil?
    abort "No calendar could be found/created"
  end
  scrape_all id
end
