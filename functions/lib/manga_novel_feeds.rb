require 'json'
require 'net/http'
require 'nokogiri'
require 'rss'
require 'time'
require 'uri'

module MangaNovelFeeds
  module Providers
    class << self
      def providers
        @providers ||= {}
      end

      def find(provider_id)
        providers.fetch(provider_id)
      end
    end

    class Base
      class << self
        private

        def provider_id(provider_id)
          Providers::providers[provider_id] = self
        end
      end

      private

      def u(s)
        URI.encode_www_form_component(s)
      end
    end

    class MagnetNovels < Base
      provider_id 'magnet-novels.com'

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
          maker.channel.link = "https://www.magnet-novels.com/novels/#{u novel_id}"
          maker.channel.description = novel_info['data']['synopsis']

          maker.items.do_sort = true

          novel_contents['data'].each do |section|
            next if section['status'] == 0

            unless published_at = section['public_time'] || section['latest_public_time']
              next
            end

            maker.items.new_item do |item|
              url = item.link = "https://www.magnet-novels.com/novels/#{u novel_id}/episodes/#{u section['id']}"
              item.title = section['title']
              item.date = Time.parse(published_at)
              item.guid.content = url
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class MangaCross < Base
      provider_id 'mangacross.jp'

      BASE_URI = URI('https://mangacross.jp')

      private_constant :BASE_URI

      def rss(id)
        info = JSON.parse(
          Net::HTTP.get(
            URI("https://mangacross.jp/api/comics/#{u id}.json"),
          )
        )

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = info['comic']['title']
          maker.channel.link = "https://mangacross.jp/comics/#{u id}"
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

    class Storia < Base
      provider_id 'storia.takeshobo.co.jp'

      def rss(id)
        index_uri = URI("https://storia.takeshobo.co.jp/manga/#{u id}/")
        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.xpath('//h2[text() = "ストーリー"]/following-sibling::p').text

          maker.items.do_sort = true

          index.css('.episode').each do |ep|
            next unless a = ep.ancestors('a').first
            next unless date = extract_date(ep.xpath('./following-sibling::li[text() = "公開日"]/following-sibling::li[1]').text)

            maker.items.new_item do |item|
              uri = item.link = index_uri + a.attr('href')
              item.title = ep.text.strip
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end

      private

      def extract_date(s)
        if /(?<year>\d+)年(?<month>\d+)月(?<day>\d+)日/ =~ s
          Time.new(year.to_i, month.to_i, day.to_i, 0, 0, 0, '+09:00')
        end
      end
    end

    class GanganOnline < Base
      provider_id 'ganganonline.com'

      def rss(id)
        index_uri = URI("https://www.ganganonline.com/title/#{u id}")
        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        data = JSON.parse(index.at_css('#__NEXT_DATA__').text)
        props = data.dig('props', 'pageProps', 'data', 'default')

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = props['description']

          maker.items.do_sort = true

          props['chapters'].each do |entry|
            next unless /(?<year>\d+)\.(?<month>\d+)\.(?<mday>\d+)/ =~ entry['publishingPeriod']
            date = Time.new(year.to_i, month.to_i, mday.to_i)
            title = entry.values_at('mainText', 'subText').compact.join(?\s)
            uri = "https://www.ganganonline.com/title/#{u id}/chapter/#{u entry['id']}"

            maker.items.new_item do |item|
              item.link = uri
              item.title = title
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class UraSunday < Base
      provider_id 'urasunday.com'

      def rss(id)
        index_uri = URI("https://urasunday.com/title/#{u id}")
        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.at_css('meta[name="description"]').attr('content')

          maker.items.do_sort = true

          index.css('.chapter li:not(.charge)').each do |entry|
            link = entry.at_css('a')
            divs = link.css('div > div:not(.new)').to_a
            fail 'Unexptected HTML structure' unless divs.size == 3
            time = Time.strptime(divs[2].text + ' +0900', '%Y/%m/%d %z')
            title = divs[...2].map(&:text).join(?\s)

            maker.items.new_item do |item|
              uri = item.link = index_uri + link.attr('href')
              item.title = title
              item.date = time
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class WebNewType < Base
      provider_id 'comic.webnewtype.com'

      def rss(id)
        index_uri = URI("https://comic.webnewtype.com/contents/#{u id}/")
        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.title
          maker.channel.link = index_uri
          maker.channel.description = index.at_css('#WorkInfo-tab1 p').text

          maker.items.do_sort = true

          # Assume the latest chapter is published within 1 year
          today = Date.today
          last_y, last_md = today.year, [today.month, today.day]

          index.css('#episodeList li:not(.deliveryContentsSaleAD)').each do |entry|
            link = entry.at_css('a')
            title = entry.at_css('.description').text.strip
            next unless /(?<month>\d+)月(?<day>\d+)日配信/ =~ entry.at_css('.date01').text

            md = [month.to_i, day.to_i]
            last_y -= 1 if (md <=> last_md) > 0
            date = Time.new(last_y, *md)
            last_md = md

            maker.items.new_item do |item|
              uri = item.link = index_uri + link.attr('href')
              item.title = title
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end

    class WebAce < Base
      provider_id 'web-ace.jp'

      def rss(id)
        sub, id = id.split(':', 2)

        index_uri = URI("https://web-ace.jp/#{u sub}/contents/#{u id}/")
        index = Nokogiri::HTML(Net::HTTP.get(index_uri))

        RSS::Maker.make('2.0') do |maker|
          maker.channel.title = index.at_css("#sakuhin-info .credit h1").text
          maker.channel.link = index_uri
          maker.channel.description = index.at_css("#sakuhin-info .description p:not(.subtitle)").text

          maker.items.do_sort = true

          index.css('#read a').each do |entry|
            next unless m = entry.at_css('.media-body')

            title = m.at_css('p').text
            next unless /(?<year>\d+)年(?<month>\d+)月(?<mday>\d+)日/ =~ m.at_css('.updated-date').text
            date = Time.new(year.to_i, month.to_i, mday.to_i)

            maker.items.new_item do |item|
              uri = item.link = index_uri + entry.attr('href')
              item.title = title
              item.date = date
              item.guid.content = uri
              item.guid.isPermaLink = true
            end
          end
        end
      end
    end
  end
end
