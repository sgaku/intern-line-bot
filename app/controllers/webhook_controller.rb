require 'line/bot'
require 'active_support/all'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def initialize
    GENRE_ID_LIST = ["001004001","001004002","001004008","001004004","001004016"];
    GENRE_ID_LIST.freeze
  end
  
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def fetchData
    books = []
    response = RakutenWebService::Books::Book.search(booksGenreId:GENRE_ID_LIST.sample,sort:"reviewAverage")
    # 表示したいパラメータがないものを省く
      response.each do |item|
        if item.title.present? && item.item_caption.present? && item.large_image_url.present? && item.review_average.present?
          books << item
        end
      end

    show_items = books.first(10)
    return show_items[rand(10)]
  end 

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head 470
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'].include?("本") then 
            book =  fetchData
            message = build_random_book_flex(book.title,book.large_image_url,book.item_url,book.review_average,book.item_caption)       
          else
            message = {
              type: 'text',
              text: '本読みません？'
            }
          end 
          client.reply_message(event['replyToken'], message)
        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      end
    }
    head :ok
  end

  def build_random_book_flex(title,image,url,review_average,item_caption)
    {
      type: 'flex',
      altText: '本のリスト',
      contents: {
        type: 'bubble',
        hero:{
          type:'image',
          url:image,
          size:'3xl',
          aspectRatio:'2:3',
          aspectMode:'cover',
        },
        body: {
          type: 'box',
          layout: 'vertical',
          contents: [
            {
              type: 'text',
              text: title,
              wrap: true,
              size: 'sm',
            }, 
            {
              type:'box',
              layout:'baseline',
              margin:'md',
              contents: rate(review_average)
            },
            {
              type:'text',
              text:item_caption,
              wrap: true,
              size: 'sm',
            } 
          ]
        },
        footer:{
          type:'box',
          layout:'vertical',
          contents:[
            type:'button',
            style:'link',
            height:'sm',
            action:{
              type:'uri',
              label:"購入する",
              uri:url,
            }
          ]
        },
      }
    }
  end

  def rate(review_average)
    rate  = review_average.to_i
    rates = []

    5.times do |i|
    url =  if rate > i
        Settings.gold_star
      else
        Settings.gray_star
      end

    rates << {
            "type": "icon",
            "size": "sm",
            "url": url
          }
    end
      
    rates << {
          "type": "text",
          "text": rate.to_s,
          "size": "sm",
          "color": "#999999",
          "margin": "md",
          "flex": 0
        }
    return rates
  end
end
