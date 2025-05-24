require 'open3'
require 'fileutils'

class Charts
  attr_reader :charts_dir

  def initialize(path)
    @charts_dir = Pathname(path)
  end

  def expand
    chart_dirs = charts_dir.children.sort

    chart_outputs = chart_dirs.map do |chart_dir|
      chart_name = chart_dir.basename.to_s

      ct_values = chart_dir/'ci'/'ct-values.yaml'

      args = if ct_values.exist?
        ['-f', ct_values.to_path]
      else
        []
      end

      FileUtils.rm_f chart_dir/'Chart.lock'

      out, status = Open3.capture2e('helm', 'dependency', 'build', chart_dir.to_path)
      raise out unless status.success?

      out, err, status = Open3.capture3('helm', 'template', chart_name, chart_dir.to_path, *args)
      raise err unless status.success?

      YAML.load_stream(out).compact
    end
  end
end
