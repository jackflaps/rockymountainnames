#!/usr/bin/env ruby

# aspace_converter.rb - converts ArchivesSpace agent JSON objects to RDF
# * Uses the CoLA data dictionary where necessary but is mostly FoaF
# * Uses the generic 'sort_name' attribute instead of being more granular by agent type

require 'date'
require 'rdf'
require 'linkeddata'
require_relative 'astools'

@log = "export_log_#{DateTime.now.strftime("%Y%m%d_%H%M%S")}.txt"
# list of local ArchivesSpace users -- not to be exported as RDF
@users = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,12832,12956,12957,13305,13306,13308,13309,13310,13311,13312,13313,13314,13322,13800,13814,13918,14021,14022,14118,14119,14120,14121,14122,14123,14124,14125,14126,14127,14611,14800,14801,14915,14969,14970,15146,15375,15405,15406,15427,15453,15454,15455,15456,15457,15458,15535,15599,15716]

def write_to_rdf(agent, id, type)
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

  File.open(@log, 'a') { |f| f.write("Writing #{id}.ttl\n") }
  resource = RDF::URI.new("http://cola.jackflaps.net/cola/#{id}")

  graph = RDF::Graph.new
  graph << RDF::Statement.new(resource, RDF.type, rdfs_type)
  graph << RDF::Statement.new(resource, cola.display_name, agent["title"])

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

  File.delete("rdf/#{id}.nt") if File.exist?("rdf/#{id}.nt")
  File.open("rdf/#{id}.nt", 'w') { |f| f.write(graph.dump(:ntriples)) }
end

def rdf_convert(type)
  ids = ASTools::HTTP.get_json("/agents/#{type}", 'all_ids' => true)
  ids.each do |id|
    agent = ASTools::HTTP.get_json("/agents/#{type}/#{id}")
    agent_rdf = write_to_rdf(agent, id, type)
  end
end

ASTools::User.get_session
["people", "corporate_entities", "families"].each {|type| rdf_convert(type)}
