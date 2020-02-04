require 'json'
require 'net/http'
require 'rss'
require 'time'
require 'uri'

module MangaNovelFeeds
  module Providers
    class MagnetNovels
      API_GET_NOVEL_INFO = URI('https://www.magnet-novels.com/api/novel/reader/getNovelInfo')
      API_GET_NOVEL_CONTENTS = URI('https://www.magnet-novels.com/api/web/v2/reader/getNovelContents')

      def rss(novel_id)
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

        RSS::Maker.make('2.0') do |maker|
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
      end
    end

    class MangaCross
      BASE_URI = URI('https://mangacross.jp')

      def rss(id)
        info = JSON.parse(
          Net::HTTP.get(
            URI("https://mangacross.jp/api/comics/#{id}.json"),
          )
        )

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = info['comic']['title']
          maker.channel.link = "https://mangacross.jp/comics/#{id}"
          maker.channel.description = info['comic']['seo_outline']

          maker.items.do_sort = true

          info['episodes'].each do |episode|
            next if episode['status'] == 'private'

            unless published_at = episode['publish_start'] || episode['member_publish_start']
              next
            end

            maker.items.new_item do |item|
              url = item.link = BASE_URI + episode['page_url']
              item.title = [episode['volume'], episode['title']].join(?\s).strip
              item.date = Time.parse(published_at)
              item.guid.content = url
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end
  end

  PROVIDERS = {
    'magnet-novels.com' => Providers::MagnetNovels.new,
    'mangacross.jp' => Providers::MangaCross.new,
  }
end
