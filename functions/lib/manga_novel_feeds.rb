require 'json'
require 'net/http'
require 'nokogiri'
require 'rss'
require 'time'
require 'uri'

module MangaNovelFeeds
  module Providers
    class << self
      def find(name)
        constants(false).each do |const|
          klass = const_get(const)
          return klass if klass.const_get(:NAME, false) == name
        end
      end
    end

    class MagnetNovels
      NAME = 'magnet-novels.com'

      API_GET_NOVEL_INFO = URI('https://www.magnet-novels.com/api/novel/reader/getNovelInfo')
      API_GET_NOVEL_CONTENTS = URI('https://www.magnet-novels.com/api/web/v2/reader/getNovelContents')

      private_constant :API_GET_NOVEL_INFO, :API_GET_NOVEL_CONTENTS

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
      NAME = 'mangacross.jp'

      BASE_URI = URI('https://mangacross.jp')

      private_constant :BASE_URI

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

          info['comic']['episodes'].each do |episode|
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

    class Storia
      NAME = 'storia.takeshobo.co.jp'

      def rss(id)
        index_uri = URI("https://storia.takeshobo.co.jp/manga/#{id}/")

        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.css('.work_sammary').first.text

          maker.items.do_sort = true

          index.css('.box_episode > div').each do |ep|
            next unless a = ep.css('a').first

            maker.items.new_item do |item|
              uri = item.link = index_uri + a.attr('href')
              item.title = ep.css('.episode_title').text[/［.*/]
              item.date = extract_date(ep.css('.episode_caption'))
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end

      private

      def extract_date(el)
        el.children.each do |c|
          if /【公開日】(?<year>\d+)年(?<month>\d+)月(?<day>\d+)日/ =~ c.content
            return Time.new(year.to_i, month.to_i, day.to_i, 0, 0, 0, '+09:00')
          end
        end

        nil
      end
    end
  end
end
