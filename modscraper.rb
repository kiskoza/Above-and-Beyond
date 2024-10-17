#!/bin/env ruby

require 'csv'
require 'debug'
require 'json'
require 'net/http'

API_KEY = "<your api key>"

def generate_csv(versions)
  CSV.open('tmp/upgrade_list.csv', 'w') do |csv|
    csv << %w[ID Current] + versions

    mod_list.each do |project_id, file_id|
      all_versions_for_mod(project_id).then do |data|
        current = current_version(data, file_id)

        csv << [project_id, current&.dig(:fileName)] + versions.map { latest_version_for_mc_version(data, _1) }.map { _1&.dig(:fileName) }
      end
    end
  end
end

def mod_list
  File.open('manifest.json').read
    .then { JSON.parse(_1, symbolize_names: true) }
    .then { _1[:files] }
    .map { [_1[:projectID], _1[:fileID]] }
end

def current_version(data, file_id)
  data.find { _1[:id] == file_id }
end

def latest_version_for_mc_version(...)
  versions_for_mc_version(...).sort_by { _1[:displayName] }.last
end

def versions_for_mc_version(data, mc_version)
  data.select { _1[:gameVersions].include?(mc_version) }
end

def all_versions_for_mod(project_id)
  file_name = "tmp/meta/mods/#{project_id}"

  unless File.exist?(file_name)
    load_all_versions_for_mod(project_id)
      .then { |data| JSON.pretty_generate({data:}) }
      .then { |json| File.open(file_name, 'w') { |file| file.write(json) } }
  end

  File.open(file_name).read
    .then { JSON.parse(_1, symbolize_names: true) }
    .then { _1[:data] }
end

def load_all_versions_for_mod(project_id)
  list_of_versions = []

  paginate_over(project_id) do |versions|
    list_of_versions += versions
  end

  list_of_versions
end

def paginate_over(project_id, &)
  offset = 0
  page_size = 50

  loop do
    print '.'
    data = load_page(project_id, page_size, offset)
    yield data[:data]

    offset += page_size
    break if data[:pagination][:totalCount] < offset
  end

  print "\n"
end

def load_page(project_id, page_size, offset)
  Net::HTTP::Get.new(URI("https://api.curseforge.com/v1/mods/#{project_id}/files?pageSize=#{page_size}&index=#{offset}"))
    .tap { _1['Accept'] = 'application/json' }
    .tap { _1['x-api-key'] = API_KEY }
    .then { |request| Net::HTTP.start('api.curseforge.com', use_ssl: true) { |http| http.request(request) } }
    .then { JSON.parse(_1.body, symbolize_names: true) }
end

generate_csv(['1.16.5', '1.17.1', '1.18.2', '1.19.4', '1.20.6', '1.21'])
