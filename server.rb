require 'sinatra'
require 'base64'
require 'faraday'
require 'json'

CHANNEL_ID     = ENV['LINE_CHANNEL_ID']
CHANNEL_SECRET = ENV['LINE_CHANNEL_SECRET']
CHANNEL_MID    = ENV['LINE_CHANNEL_MID']
OUTBOUND_PROXY = ENV['LINE_OUTBOUND_PROXY']

MAX_SEARCH_LIMIT_NUM = 2

get '/callback' do
  return 'ブラウザからのアクセスには対応していません' unless from_line?

  input = params[:result][0]
  keyword  = input['content']['text']
  from_ids = input['content']['from']

  conn = Faraday.new(url: 'http://api.gifmagazine.net') do |faraday|
    faraday.request  :url_encoded
    faraday.response :logger
    faraday.adapter  Faraday.default_adapter
  end

  response = conn.get '/v1/gifs/search', { q: keyword, limit: MAX_SEARCH_LIMIT_NUM }
  gif = JSON.parse(response.body).dig('data', (0..MAX_SEARCH_LIMIT_NUM).to_a.sample, 'image')
  original_url = gif.dig('default', 'url')
  preview_url  = gif.dig('small', 'url') || original_url

  if response.status == 200
    LineClient.new(
      CHANNEL_ID,
      CHANNEL_SECRET,
      CHANNEL_MID,
      OUTBOUND_PROXY
    ).send(from_ids, original_url, preview_url)
  else
    "うまくいきませんでした...(#{response.status})"
  end
end

def from_line?
  signature = request.env['X-LINE-ChannelSignature']
  http_request_body = request.body.read
  hash = OpenSSL::HMAC::digest(OpenSSL::Digest::SHA256.new, CHANNEL_SECRET, http_request_body)
  signature_answer = Base64.strict_encode64(hash)

  signature == signature_answer
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
    client = Faraday.new(url: LINE_BOT_END_POINT) do |faraday|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter Faraday.default_adapter
      conn.proxy @proxy
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