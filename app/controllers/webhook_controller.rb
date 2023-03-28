require 'line/bot'
require 'active_support/all'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化
  

  def initialize
    # 小説の中のジャンルを取得(001004)
    response = RakutenWebService::Books::Genre.search(booksGenreId:"001004")
    @@genre_list = response.first
  end

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  # 楽天APIを呼んで本のデータを取得する
  def fetch_books_data(genre_id)
    books = []
    # ジャンルid、高レート順に指定
    response = RakutenWebService::Books::Book.search(booksGenreId:genre_id,sort:"reviewAverage")
    # 表示したいパラメータがないものを省く
      response.each do |item|
        if item.title.present? && item.item_caption.present? && item.large_image_url.present? && item.review_average.present?
          books << item
        end
      end

      # 30個のレスポンスからランダムで10個返す
    return books.sample(10)
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
        # hashに変換
        postback_data = URI.decode_www_form(event['postback']['data']).to_h
        # ポストバックのジャンルidから検索をかける
        books =  fetch_books_data(postback_data['genreId'])
        #フレックスメッセージのデータを取得
        message = build_flex_book_list(books)    
       
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'].include?("本") then 
            # ジャンルリストからジャンルのフレックスメッセージ表示
              message = build_genre_list_flex(@@genre_list.children)    
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

# ジャンルリストのフレックスメッセージ
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

# ジャンルリストのボタン
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

  # カルーセルを返す
  def build_flex_book_list(books)
    {
      type: 'flex',
      altText: 'カルーセル',
      contents: {
        type: 'carousel',
        contents: books.map {|book| book_list_item(book)}
      }  
    } 
  end

  # カルーセル内のアイテム
  def book_list_item(book)
     {
        type: 'bubble',
        hero:{
          type:'image',
          url:book['largeImageUrl'],
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
              text: book['title'],
              wrap: true,
              size: 'sm',
            }, 
            {
              type:'box',
              layout:'baseline',
              margin:'md',
              contents: rate(book['reviewAverage'])
            },
            {
              type:'text',
              text:book['itemCaption'],
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
              uri:book['itemUrl'],
            }
          ]
        },
      }
  end

  # 評価レートの判定
  def rate(review_average)
    rate  = review_average.to_i
    rates = []

    # 5段階評価
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
    # 評価数表示
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
