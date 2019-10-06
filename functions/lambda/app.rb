require 'digest/sha1'
require 'json'
require 'net/http'
require 'rss'
require 'time'
require 'uri'

ENV['TZ'] = 'UTC'

API_GET_NOVEL_INFO = URI('https://www.magnet-novels.com/api/novel/reader/getNovelInfo')
API_GET_NOVEL_CONTENTS = URI('https://www.magnet-novels.com/api/web/v2/reader/getNovelContents')

def handler(event:, context:)
  novel_id = event['pathParameters'].fetch('novelId')

  novel_info_t = Thread.new do
    JSON.parse(
      Net::HTTP.post(
        API_GET_NOVEL_INFO,
        {"novel_id" => novel_id.to_s}.to_json,
        "Content-Type" => "application/json"
      ).body
    )
  end

  novel_contents_t = Thread.new do
    JSON.parse(
      Net::HTTP.post(
        API_GET_NOVEL_CONTENTS,
        {"novel_id" => novel_id.to_s}.to_json,
        "Content-Type" => "application/json"
      ).body
    )
  end

  novel_info = novel_info_t.value
  novel_contents = novel_contents_t.value

  rss = RSS::Maker.make('2.0') do |maker|
    maker.channel.title = novel_info['data']['name']
    maker.channel.link = "https://www.magnet-novels.com/novels/#{novel_id}"
    maker.channel.description = novel_info['data']['synopsis']

    maker.items.do_sort = true

    novel_contents['data'].each do |section|
      next if section['status'] == 0

      unless published_at = section['public_time'] || section['latest_public_time']
        next
      end

      maker.items.new_item do |item|
        url = item.link = "https://www.magnet-novels.com/novels/#{novel_id}/episodes/#{section['id']}"
        item.title = section['title']
        item.date = Time.parse(published_at)
        item.guid.content = url
        item.guid.isPermaLink = true
      end
    end
  end

  rss_text = rss.to_s
  rss_etag = Digest::SHA1.hexdigest(rss_text)

  {
    'statusCode' => 200,
    'body' => rss_text,
    'headers' => {
      'Content-Type' => 'application/rdf+xml',
      'Cache-Control' => 'public, s-maxage=600',
      'ETag' => rss_etag,
    },
  }
end
