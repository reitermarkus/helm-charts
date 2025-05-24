#!/usr/bin/env ruby

require 'json'
require 'pathname'
require 'open3'

require_relative 'charts'
require_relative 'diff_yaml'

charts_dir, path_a, path_b, * = ARGV

charts_dir = Pathname(charts_dir)
path_a = Pathname(path_a)
path_b = Pathname(path_b)

charts_a = Charts.new(path_a/charts_dir)
charts_a_expanded = charts_a.expand

charts_b = Charts.new(path_b/charts_dir)
charts_b_expanded = charts_b.expand

diff = diff_yaml(charts_a_expanded, charts_b_expanded)

summary = []

summary << if diff
  <<~MARKDOWN
    Diff:

    ```diff
    #{diff}
    ```
  MARKDOWN
else
  'No resource changes detected.'
end

summary = summary.join("\n")

if ENV.key?('GITHUB_STEP_SUMMARY') && ENV.key?('GITHUB_OUTPUT')
  step_summary = Pathname(ENV.fetch('GITHUB_STEP_SUMMARY'))
  step_summary.write summary

  output = Pathname(ENV.fetch('GITHUB_OUTPUT'))
  if diff
    File.write "#{path_b.basename}.diff", diff

    query = ''
    if %w[pull_request pull_request_target].include?(ENV.fetch('GITHUB_EVENT_NAME'))
      event = JSON.parse(File.read(ENV.fetch('GITHUB_EVENT_PATH')))
      query += "?pr=#{event.fetch('pull_request').fetch('number')}"
    end

    api_url = ENV.fetch('GITHUB_API_URL')
    repo = ENV.fetch('GITHUB_REPOSITORY')
    github_token = ENV.fetch('GITHUB_TOKEN')
    run_id = ENV.fetch('GITHUB_RUN_ID')
    job_name = ENV.fetch('GITHUB_JOB')
    run_attempt = ENV.fetch('GITHUB_RUN_ATTEMPT')

    out, err, status = Open3.capture3(
      'curl',
      '--location',
      '--silent',
      '--fail',
      '--header', 'Accept: application/vnd.github+json',
      '--header', "Authorization: Bearer #{github_token}",
      '--header', 'X-GitHub-Api-Version: 2022-11-28',
      "#{api_url}/repos/#{repo}/actions/runs/#{run_id}/attempts/#{run_attempt}/jobs",
    )
    raise err unless status.success?

    jobs = JSON.parse(out).fetch('jobs')

    # FIXME: https://github.com/ipdxco/job-summary-url-action/issues/12
    job_name = 'charts'

    job = jobs.find { |job| job.fetch('name') == job_name }
    job_id = job.fetch('id')
    run_url = "https://github.com/#{repo}/actions/runs/#{run_id}#{query}#summary-#{job_id}"

    comment = if diff&.length <= 60_000
      <<~OUTPUT
        <details>
          <summary>Resources have changed.</summary>

        ```diff
        #{diff}
        ```

        </details>

        View the complete diff at #{run_url}.
      OUTPUT
    else
      <<~OUTPUT
        Resources have changed.

        View the complete diff at #{run_url}.
      OUTPUT
    end

    output.write <<~OUTPUT
      comment<<EOF
      <!-- helm-chart-differ -->
      #{comment}
      EOF
    OUTPUT
  else
    output.write <<~OUTPUT
      comment<<EOF
      <!-- helm-chart-differ -->
      No resources have changed.
      EOF
    OUTPUT
  end
else
  puts summary
end
