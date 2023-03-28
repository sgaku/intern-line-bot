require 'line/bot'
require 'active_support/all'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化
  GENRE_ID_LIST = ["001004001","001004002","001004008","001004004","001004016"];
 GENRE_ID_LIST.freeze
  

 def initialize
  
  response = RakutenWebService::Books::Genre.search(booksGenreId:"001004")
  @@genre_list = response.first
logger.debug"genre_list:#{@@genre_list}"
 end
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def fetchData(genre_id)
    books = []
    response = RakutenWebService::Books::Book.search(booksGenreId:genre_id,sort:"reviewAverage")
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
      when Line::Bot::Event::Postback
        postback_data = URI.decode_www_form(event['postback']['data']).to_h
        book =  fetchData(postback_data['genreId'])
        message = build_random_book_flex(book.title,book.large_image_url,book.item_url,book.review_average,book.item_caption)    
        # message = build_postback_book_list(postback_data)
     
        
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'].include?("本") then 
           @@genre_list.children.map {|child| puts child}
            message = build_genre_list_flex(@@genre_list.children)
            # logger.debug"message:#{message}"
            # book =  fetchData
            # message = build_random_book_flex(book.title,book.large_image_url,book.item_url,book.review_average,book.item_caption)       
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

  def build_postback_book_list(data)
  end

  def build_genre_list_flex(children)
    {
      type: 'flex',
      altText: 'ジャンルリスト',
      contents: {
        type: 'bubble',
        header: {
            type: 'box',
            layout: 'vertical',
            contents: [
              {
                type: 'text',
                size: 'lg',
                text: "好きなジャンルを選んでください"
              }
            ]
          },
        body: {
          type: 'box',
          layout: 'vertical',
          contents:children.map {|child| genre_button(child)}
        },
      }
    }
  end


  def genre_button(genre)
      {
        type:'box',
        layout:'horizontal',
        contents:[
          {
            type:'text',
            text:genre['booksGenreName'],
            gravity:'center',
            size:'sm',
            align: 'start'
          },
          {
            type:'button',
           height:'sm',
           action:{
            type:'postback',
            label:'調べる',
            displayText:genre['booksGenreName'],
            data:"type=genre_search&genreId=#{genre['booksGenreId']}"
           }
          }, 
        ]
      }
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
