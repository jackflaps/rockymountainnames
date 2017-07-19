require 'net/http'
require 'json'
require 'uri'
require 'io/console'

module ASTools

  def self.backend_url
    # the config.rb default; set this to whatever your backend URL is
    "http://localhost:8089"
  end

  def self.store_user_session(session)
    Thread.current[:backend_session] = session
  end

  module User

    def self.get_session(opts = {})
      puts "Logging into ArchivesSpace at #{ASTools.backend_url}... "
      unless opts[:login]
        print "login: "
        opts[:login] = gets.chomp
      end
      unless opts[:password]
        print "password: "
        opts[:password] = STDIN.noecho(&:gets).chomp
      end
      print "\n"

      uri = URI("#{ASTools.backend_url}/users/#{opts[:login]}/login")
      response = Net::HTTP.post_form(uri, 'password' => opts[:password])
      if response.is_a?(Net::HTTPSuccess) || response.code == "200"
        ASTools.store_user_session(JSON.parse(response.body)['session'])
      else
        puts JSON.parse(response.body)['error']
        get_session
      end
    end

  end

  module HTTP

    def self.backend_url
      ASTools.backend_url
    end

    def self.current_backend_session
      Thread.current[:backend_session]
    end

    def self.do_http_request(url, req)
      req['X-ArchivesSpace-Session'] = current_backend_session
      begin
        response = Net::HTTP.start(url.host, url.port) {|http| http.request(req)}
      rescue StandardError
        puts "Connection lost. Retrying in ten seconds... "
        sleep(10)
        retry
      end
      response
    end

    def self.get_response(url)
      req = Net::HTTP::Get.new(url)
      do_http_request(url, req)
    end

    def self.get_data(uri, params = {})
      uri = URI("#{backend_url}#{uri}")
      uri.query = URI.encode_www_form(params)

      response = get_response(uri)

      if response.is_a?(Net::HTTPSuccess) || response.code == "200"
        response.body
      elsif response.code == "412"
        puts "Session expired or not found. Refreshing..."
        ASTools::User.get_session
      else
        nil
      end
    end

    def self.get_json(uri, params = {})
      uri = URI("#{backend_url}#{uri}")
      uri.query = URI.encode_www_form(params)

      response = get_response(uri)

      if response.is_a?(Net::HTTPSuccess) || response.code == "200"
        JSON.parse(response.body)
      elsif response.code == "412"
        puts "Session expired or not found. Refreshing..."
        ASTools::User.get_session
      else
        nil
      end
    end

    def self.post_json(uri, json)
      uri = URI("#{backend_url}#{uri}")
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = "application/json"
      req.body = json.to_json

      do_http_request(uri, req)
    end

  end

end
