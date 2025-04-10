#!/usr/bin/env ruby

require 'open3'
require 'yaml'

# Ensure `git` outputs English error messages.
ENV["LANG"] = 'en_US'

base_branch, chart, * = ARGV

raise "No base branch specified." if base_branch.nil?
raise "No chart specified." if chart.nil?

chart_yaml_path = "#{chart}/Chart.yaml"

out, err, status = Open3.capture3('git', 'show', '--quiet', "#{base_branch}:#{chart_yaml_path}")

before = if status.success?
  YAML.safe_load(out)
else
  # Ignore charts that did not exist before.
  return if err.include?('exists on disk, but not in')

  raise err
end

after_content = File.read(chart_yaml_path)
after = YAML.safe_load(after_content)

version_before = before.fetch('version')
version_after = after.fetch('version')

return unless version_before == version_after

def split_version(version)
  version.split('.', 3).map { Integer(_1) }
end

def change_level(version_before, version_after)
  return if version_before == version_after

  major_before, minor_before, patch_before = split_version(version_before)
  major_after, minor_after, patch_after = split_version(version_after)

  return :major unless major_before == major_after
  return :minor unless minor_before == minor_after

  :patch
end

def dependency_change_levels(before, after)
  dependencies_before = before.fetch('dependencies', []).map { [_1.fetch('name'), _1] }.to_h
  dependencies_after = after.fetch('dependencies', []).map { [_1.fetch('name'), _1] }.to_h

  dependency_names = (dependencies_before.keys + dependencies_after.keys).uniq

  dependency_names.map { |dep_name|
    dep_before = dependencies_before[dep_name]
    dep_after = dependencies_after[dep_name]

    if dep_before && dep_after
      change_level(dep_before.fetch('version'), dep_after.fetch('version'))
    else
      # Dependency added/removed.
      :minor
    end
  }.compact
end

app_version_before = before.fetch('appVersion')
app_version_after = after.fetch('appVersion')

change_level = [
  *change_level(app_version_before, app_version_after),
  *dependency_change_levels(before, after)
].max_by { { major: 3, minor: 2, patch: 1 }.fetch(_1) }

def increment_version(version, change_level)
  major, minor, patch = split_version(version)

  case change_level
  when :major
    major += 1
    minor = 0
    patch = 0
  when :minor
    minor += 1
    patch = 0
  when :patch, nil
    patch += 1
  end

  "#{major}.#{minor}.#{patch}"
end

new_version = increment_version(version_after, change_level)

puts "Changing version for #{chart} from #{version_after} to #{new_version}."
new_content = after_content.sub(/^version:\s+#{Regexp.escape(version_after)}/, "version: #{new_version}")
File.write chart_yaml_path, new_content

File.open(ENV.fetch('GITHUB_OUTPUT'), 'a+') do |f|
  f.puts "new-version=#{new_version}"
end
