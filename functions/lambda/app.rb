ENV['TZ'] = 'UTC'

require 'json'
require 'digest/sha1'
require 'uri'
require_relative '../lib/manga_novel_feeds'

$providers = Hash.new {|h, k| h[k] = MangaNovelFeeds::Providers.find(k)&.new }

def handler(event:, context:)
  puts JSON.dump(event['pathParameters'])
  content_provider = event['pathParameters'].fetch('contentProvider')
  content_id = event['pathParameters'].fetch('contentId')

  unless provider = $providers[content_provider]
    return {
      'statusCode' => 404,
    }
  end

  begin
    rss = provider.rss(content_id)
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
  rescue MangaNovelFeeds::Redirect => e
    {
      'statusCode' => 302,
      'header' => {
        'Location' => e.target,
      },
    }
  rescue MangaNovelFeeds::Gone => e
    {
      'statusCode' => 410,
    }
  end
end
