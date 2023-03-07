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
parser = OptionParser.new("Usage: cube-build [options] RECIPE BUILD_DIR")
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
if non_options.length != 2
    $stderr.puts parser
    exit 1
end
non_options.map! {|s| s.scrub!}
recipe, build_dir = non_options

recipe = File.realdirpath(recipe)

fatal "#{build_dir} does not exist" if not File.exist?(build_dir)
fatal "#{build_dir} is not a directory" if not File.directory?(build_dir)
fatal "#{build_dir} is not empty" if not options.include?(:continue) and not Dir.empty?(build_dir)
build_dir = File.realpath(build_dir) + "/"

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

if recipe_data.fetch("c", []).length != 1
    fatal "recipe file must have exactly one `c` line"
end
cube_dir = Pathname.new recipe_data["c"][0]

if options.include?(:impure)
    if options[:impure].start_with?("/")
        fatal "package name cannot start with `/`"
    end
    output_dir = cube_dir + options[:impure]
else
    fatal "pure packages aren't supported yet"
    # TODO: hash the recipe file and dir to get output_dir
end

Tempfile.create('config') do |config| Tempfile.create('result') do |result|
    config.puts "output_dir #{output_dir}"
    config.puts "threads #{options[:threads]}"
    inputs = {}
    recipe_data.fetch("i", []).each do |input|
        input_alias, input_id = input.split(" ", 2)
        if input_id.start_with?("/")
            fatal "`i` alias cannot start with `/`"
        end
        config.puts "input #{input_alias} #{cube_dir + input_id}/"
        if inputs.include?(input_alias)
            fatal "duplicate `i` alias in recipe file"
        end
        inputs[input_alias] = input_id
    end
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
        if not recipe_data["i"].include?(interpreter_package_alias)
            fatal "no `i` alias matching `b` alias #{interpreter_package_alias}"
        end
        interpreter_path = cube + inputs[interpreter_package_alias] + interpreter
    end

    build_script = "#{recipe}/build"
    begin
        unsetenv_others = interpreter_package_alias != "-"
        pid = Process.spawn(
            interpreter, build_script, config.path, recipe, result.path, chdir: build_dir, pgroup: true,
            in: "/dev/null", unsetenv_others: unsetenv_others)
        _, status = Process.wait2 pid
        pid = nil
    ensure
        if pid != nil
            Process.kill("TERM", -pid)
            puts "Waiting for build script to exit..."
            Process.wait2 pid
        end
    end
    if status.exitstatus != 0
        fatal "build script failed"
    end

    result_data = {}
    result.each_line do |line|
        line.chomp!
        line.scrub!
        key, value = line.split(" ", 2)
        if result_data.include?(key)
            fatal "result file has duplicate key #{key}"
        end
        result_data[key] = value
    end

    if not result_data.include?("staging_dir")
        fatal "result file is missing the staging_dir item"
    end
    puts "Staging directory: #{result_data["staging_dir"]}"
end end
