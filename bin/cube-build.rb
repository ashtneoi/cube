#!/usr/bin/env ruby
require 'optparse'
require 'pathname'
require 'tempfile'

def fatal(s)
    $stderr.puts "Error: #{s}"
    exit 1
end

options = {
    threads: 1,
}
parser = OptionParser.new("Usage: cube-build [options] RECIPE BUILD_DIR STAGING_DIR")
parser.on('-t N', '--threads N', Integer) do |value|
    if value <= 0
        $stderr.puts "Error: -t/--threads value must be positive"
        exit(false)
    end
    value
end
parser.on('-i NAME', '--impure=NAME')
parser.on('-c', '--continue')
parser.on('-n', '--dry-run')
non_options = parser.permute!(into: options)
if non_options.length != 3
    $stderr.puts parser
    exit 1
end
non_options.map! {|s| s.scrub!}
recipe, build_dir, staging_dir = non_options

recipe = File.realdirpath(recipe)

fatal "#{build_dir} does not exist" if not File.exist?(build_dir)
fatal "#{build_dir} is not a directory" if not File.directory?(build_dir)
fatal "#{build_dir} is not empty" if not options.include?(:continue) and not Dir.empty?(build_dir)
build_dir = File.realpath(build_dir)

fatal "#{staging_dir} does not exist" if not File.exist?(staging_dir)
fatal "#{staging_dir} is not a directory" if not File.directory?(staging_dir)
fatal "#{staging_dir} is not empty" if not options.include?(:continue) and not Dir.empty?(staging_dir)
staging_dir = File.realpath(staging_dir)

recipe_data = Hash.new {|h, k| raise "missing key #{k} in #{h}"}
File.open(recipe + ".rec", "r") do |recipe_file|
    recipe_file.each_line do |line|
        line.chomp!
        line.scrub!
        key, value = line.split(" ", 2)
        if recipe_data.include?(key)
            if recipe_data[key].include?(value)
                fatal "duplicate directive `#{key} #{value}` in recipe file"
                exit 1
            end
            recipe_data[key] << value
        else
            recipe_data[key] = [value]
        end
    end
end

if recipe_data.fetch("x", []).include?("impure")
    if not options.include?(:impure)
        fatal "this package is impure (`x impure`) and requires the -i/--impure option"
    end
end

if options.include?(:impure)
    if options[:impure].start_with?("/")
        fatal "package name cannot start with `/`"
    end
    if recipe_data["c"].length != 1
        fatal "recipe file must have exactly one `c` line"
    end
    output_dir = Pathname.new(recipe_data["c"][0]) + options[:impure]
else
    fatal "pure packages aren't supported yet"
    # TODO: hash the recipe file and dir to get output_dir
end

Tempfile.create('config') do |config|
    config.puts "staging-dir #{staging_dir}"
    config.puts "output-dir #{output_dir}"
    config.puts "threads #{options[:threads]}"
    config.flush

    if not options.include?(:impure)
        fatal "pure packages aren't supported yet"
        # TODO: pure packages can't use the `-` interpreter package alias
    end

    if recipe_data["b"].length != 1
        fatal "recipe file must have exactly one `b` line"
    end
    interpreter_package_alias, interpreter = recipe_data["b"][0].split(" ", 2)
    if interpreter_package_alias == "-"
        if not recipe_data.fetch("x", []).include?("impure")
            fatal "this package's `b` alias is `-`, so it requires an `x impure` line"
        end
        interpreter_path = interpreter
    else
        fatal "for now, `b` alias must be `-`"
        # TODO: compute interpreter path
    end

    build_script = "#{recipe}/build"
    begin
        unsetenv_others = interpreter_package_alias != "-"
        pid = Process.spawn(
            interpreter, build_script, config.path, recipe, chdir: build_dir, pgroup: true,
            in: "/dev/null", unsetenv_others: unsetenv_others)
        _, status = Process.wait2 pid
        pid = nil
        exit status.exitstatus
    ensure
        if pid != nil
            Process.kill("TERM", -pid)
        end
    end
end
