ENV['TZ'] = 'UTC'

require 'digest/sha1'
require_relative '../lib/manga_novel_feeds'

def handler(event:, context:)
  content_provider = event['pathParameters'].fetch('contentProvider')
  content_id = event['pathParameters'].fetch('contentId')

  provider = MangaNovelFeeds::PROVIDERS.fetch(content_provider)
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
end
