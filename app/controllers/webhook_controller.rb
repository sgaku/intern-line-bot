require 'line/bot'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def initialize
    @@gerne_list = ["001004001","001004002","001004008","001004004","001004016"];
  end
  
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def fetchData
    books = RakutenWebService::Books::Book.search(booksGenreId:@@gerne_list[rand(5)],sort:"reviewAverage")
    return books.first
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
            message = flex(book.title,book.large_image_url,book.item_url)
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

  def flex(title,image,url)
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
end
