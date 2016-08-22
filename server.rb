require 'sinatra'
require 'base64'
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'logger'

CHANNEL_ID     = ENV['LINE_CHANNEL_ID']
CHANNEL_SECRET = ENV['LINE_CHANNEL_SECRET']
CHANNEL_MID    = ENV['LINE_CHANNEL_MID']
OUTBOUND_PROXY = ENV['LINE_OUTBOUND_PROXY']

MAX_SEARCH_LIMIT_NUM = 2

post '/callback' do
  logger = Logger.new(STDOUT)

  # TODO: LINE からのアクセスかどうかの認証を入れる

  input = JSON.parse(request.body.read).dig('result', 0)
  logger.info "ACCESSED #{input}"
  keyword  = input['content']['text']
  from_ids = input['content']['from']

  conn = Faraday.new(url: 'http://api.gifmagazine.net') do |faraday|
    faraday.request  :url_encoded
    faraday.response :logger
    faraday.adapter  Faraday.default_adapter
  end

  logger.info "GIF SEARCH: #{keyword}"
  response = conn.get '/v1/gifs/search', { q: keyword, limit: MAX_SEARCH_LIMIT_NUM }

  gif = JSON.parse(response.body).dig('data', (0..MAX_SEARCH_LIMIT_NUM - 1).to_a.sample, 'image')
  original_url = gif.dig('default', 'url')
  preview_url  = gif.dig('small', 'url') || original_url

  if response.status == 200
    response = LineClient.new(
      CHANNEL_ID,
      CHANNEL_SECRET,
      CHANNEL_MID,
      OUTBOUND_PROXY
    ).send(from_ids, original_url, preview_url)
    logger.info "LINE CHAT SENT: #{response}"
  end
end

class LineClient
  LINE_BOT_ENDPOINT = 'https://trialbot-api.line.me'
  LINE_BOT_REQUEST_PATH = '/v1/events'
  TO_CHANNEL = 1383378250
  EVENT_TYPE = '138311608800106203'

  def initialize(channel_id, channel_secret, channel_mid, proxy = nil)
    @channel_id = channel_id
    @channel_secret = channel_secret
    @channel_mid = channel_mid
    @proxy = proxy
  end

  def send(line_ids, image_url, preview_url)
    client = Faraday.new(url: LINE_BOT_ENDPOINT) do |faraday|
      faraday.request :json
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
      faraday.proxy @proxy
    end

    client.post do |request|
      request.url LINE_BOT_REQUEST_PATH
      request.headers = {
          'Content-type' => 'application/json; charset=UTF-8',
          'X-Line-ChannelID' => @channel_id,
          'X-Line-ChannelSecret' => @channel_secret,
          'X-Line-Trusted-User-With-ACL' => @channel_mid
      }
      request.body = {
        to: line_ids,
        content: {
            contentType: 2, # Image
            toType: 1, # Type of recipient set in the to property ( user = 1 ),
            originalContentUrl: image_url,
            previewImageUrl: preview_url
        },
        toChannel: TO_CHANNEL,
        eventType: EVENT_TYPE
      }
    end
  end
end
