#!/usr/bin/env ruby

# aspace_converter.rb - converts ArchivesSpace agent JSON objects to RDF
# * Uses the CoLA data dictionary where necessary but is mostly FoaF
# * Uses the generic 'sort_name' attribute instead of being more granular by agent type

require 'date'
require 'json'
require 'rdf'
require 'linkeddata'
require 'io/console'
require 'net/http'
require 'uri'

def get_token(params)
  unless (params['login'] && params['password'])
    print "login: "
    params['login'] = gets.chomp
    print "password: "
    params['password'] = STDIN.noecho(&:gets).chomp
    print "\n"
  end
  uri = URI("#{params['url']}users/#{params['login']}/login")
  resp = Net::HTTP.post_form(uri, 'password' => params['password'])
  case resp.code
  when "200"
    return JSON.parse(resp.body)['session']
  else
    puts JSON.parse(resp.body)['error']
    get_token(params)
  end
end

def get_request(obj, params, opts = {})
  uri = URI(params['url'])
  req = Net::HTTP::Get.new(obj)
  req.set_form_data(opts) unless opts.empty?
  req['X-ArchivesSpace-Session'] = params['token']
  resp = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  case resp.code
  when "200"
    return resp
  when "412"
    error_code = JSON.parse(resp.body)['code'] rescue nil
    if error_code == "SESSION_EXPIRED" or error_code == "SESSION_GONE"
      puts "\nSession expired. Fetching new token... "
      params['token'] = get_token(params)
      get_request(obj, params, opts)
    end
  else
    puts "An error occurred: #{resp.message}"
  end
end

def write_to_rdf(params, agent, id, type)
  cola = RDF::Vocabulary.new("http://cola.jackflaps.net/cola#")
  foaf = RDF::Vocab::FOAF
  owl = RDF::Vocab::OWL

  id, rdfs_type = case type
  when "people"
    ["p#{id.to_s.rjust(7,"0")}", foaf.Person]
  when "corporate_entities"
    ["c#{id.to_s.rjust(7,"0")}", foaf.Organization]
  when "families"
    ["f#{id.to_s.rjust(7,"0")}", foaf.Group]
  end

  File.open(params['log'], 'a') { |f| f.write("Writing #{id}.ttl\n") }

  resource = RDF::URI.new("http://cola.jackflaps.net/cola/#{id}")

  graph = RDF::Graph.new
  graph << RDF::Statement.new(resource, RDF.type, rdfs_type)

  agent['names'].each do |name|
    id_bnode = RDF::Node.new
    graph << RDF::Statement.new(id_bnode, RDF.type, RDF::URI.new(cola.identity))
    graph << RDF::Statement.new(id_bnode, foaf.name, RDF::Literal.new(name["sort_name"]))
    if name["authorized"]
      graph << RDF::Statement.new(id_bnode, RDF::URI.new(cola.hasForm), RDF::Literal.new("authorized"))
    else
      graph << RDF::Statement.new(id_bnode, RDF::URI.new(cola.hasForm), RDF::Literal.new("alternative"))
    end
    graph << RDF::Statement.new(id_bnode, RDF::URI.new(cola.hasRules), RDF::Literal.new(name["rules"]))
    if name["authority_id"]
      if name["authority_id"].start_with?('http://')
        graph << RDF::Statement.new(id_bnode, owl.sameAs, RDF::URI.new(name["authority_id"]))
      end
    end
    graph << RDF::Statement.new(resource, RDF::URI.new(cola.hasIdentity), id_bnode)
  end

  agent['notes'].each do |note|
    if note["jsonmodel_type"] == "note_bioghist"
      note["subnotes"].each do |subnote|
        graph << RDF::Statement.new(resource, RDF::URI.new(cola.hasBiogHist), RDF::Literal.new(subnote["content"]))
      end
    end
  end

  maint_bnode = RDF::Node.new
  graph << RDF::Statement.new(maint_bnode, RDF.type, RDF::URI.new(cola.maintenanceEvent))
  graph << RDF::Statement.new(maint_bnode, RDF::URI.new(cola.eventType), RDF::URI.new(cola.created))
  graph << RDF::Statement.new(maint_bnode, RDF::URI.new(cola.eventAgent), RDF::Literal.new("kclair"))
  graph << RDF::Statement.new(resource, RDF::URI.new(cola.hasMaintenanceEvent), maint_bnode)

  File.delete("rdf/#{id}.ttl") if File.exist?("rdf/#{id}.ttl")
  File.open("rdf/#{id}.ttl", 'w') { |f| f.write(graph.dump(:turtle)) }
end

def rdf_convert(params, type)
  request_url = "#{params['url']}agents/#{type}"
  ids = JSON.parse(get_request(URI("#{request_url}"), params, { 'all_ids' => true }).body)
  ids.each do |id|
    agent = JSON.parse(get_request(URI("#{request_url}/#{id}"), params).body)
    agent_rdf = write_to_rdf(params, agent, id, type)
  end
end


params = {
  'url' => "http://localhost:8089/",
  'repo_url' => "http://localhost:8089/repositories/2/",
  'types' => ["people", "corporate_entities", "families"],
  'log' => "export_log_#{DateTime.now.strftime("%Y%m%d_%H%M%S")}.txt"
}

params['token'] = get_token(params)
params['types'].each do |type|
  rdf_convert(params, type)
end
