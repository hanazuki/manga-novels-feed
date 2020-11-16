ENV['TZ'] = 'UTC'

require 'json'
require 'digest/sha1'
require 'uri'
require_relative '../lib/manga_novel_feeds'

$providers = Hash.new {|h, k| h[k] = MangaNovelFeeds::Providers.find(k).new }

def handler(event:, context:)
  puts JSON.dump(event['pathParameters'])
  content_provider = event['pathParameters'].fetch('contentProvider')
  content_id = event['pathParameters'].fetch('contentId')

  rss = $providers[content_provider].rss(URI.encode_www_form_component(content_id).gsub(?+, '%20'))
  rss_text = rss.to_s
  rss_etag = %{"#{Digest::SHA1.hexdigest(rss_text)}"}

  {
    'statusCode' => 200,
    'body' => rss_text,
    'headers' => {
      'Content-Type' => 'application/rss+xml',
      'Cache-Control' => 'public, s-maxage=600',
      'ETag' => rss_etag,
    },
  }
end
