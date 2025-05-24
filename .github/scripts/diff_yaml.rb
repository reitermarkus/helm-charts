require 'open3'
require 'tempfile'
require 'yaml'

def diff_yaml(a, b)
  return if a == b

  file_a = Tempfile.new(%w[a yml])
  file_b = Tempfile.new(%w[b yml])
  begin
    file_a.puts YAML.dump_stream(*a)
    file_a.close
    file_b.puts YAML.dump_stream(*b)
    file_b.close

    out, err, status = Open3.capture3('diff', '-u', file_a.path, file_b.path)
    raise err unless (0..1).cover?(status.exitstatus)

    # Remove temporary file names.
    diff = out.lines[2..].join

    if diff.empty?
      nil
    else
      diff
    end
  ensure
    file_a.unlink
    file_b.unlink
  end
end
