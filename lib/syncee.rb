#!/usr/bin/env ruby

# WHAT: Synchronize snippets, templates and global variables from an ExpressionEngine site to:
#
#     ./ee/templates
#     ./ee/snippets
#     ./ee/variables
#
# HOW: Create a script. For example:
# 
#   # Require this file.
#
#   require '~/lib/syncee.rb'
#
#   # Details of one or more EE sites accessible via SSH.
#
#   sites = {
#     en: {
#       ssh_host: 'example.com',
#       db_name: 'ee',
#       db_user: 'alice',
#       db_password: 'secret',
#     },
#
#     es: {
#       ssh_host: 'example.com',
#       db_name: 'ee',
#       db_user: 'alice',
#       db_password: 'secret',
#       site_id: '2',
#     },
#   }
#   
#   # Menu to provide syncing from a choice of multiple sites.
#
#   case SyncEE.prompt_user("Example.com (e)ENGLISH (s)PANISH (a)BORT", /e|s|a/)
#   when 'e'
#     SyncEE.new sites[:en]
#
#   when 's'
#     SyncEE.new sites[:es]
#   end

require 'fileutils' # mkpath, mv
require 'io/console' # STDIN.getch

class SyncEE
  REQUIRED_ARGS = %w(ssh_host db_name db_user db_password)

  SQL = {
    site_name: 'SELECT site_name FROM exp_sites WHERE site_id = %d',
    templates: 'SELECT g.group_name, t.template_name, t.template_type, t.allow_php, t.template_data FROM exp_templates t INNER JOIN exp_template_groups g USING (group_id) WHERE t.site_id = %d',
    snippets: 'SELECT snippet_name, snippet_contents FROM exp_snippets WHERE site_id = %d',
    variables: 'SELECT variable_name, variable_data FROM exp_global_variables WHERE site_id = %d'
  }

  INPUT = {
    row: /^\*{10,} \d+\. row \*{10,}$/,

    templates: {
      name: /^\W*template_name: (\w+)$/,
      template_group: /^\W*group_name: (\w+)$/,
      template_type: /^\W*template_type: (\w+)$/,
      php_template: /^\W*allow_php: (\w+)$/,
      data: /^\W*template_data: (.+)$/,
    },

    snippets: {
      name: /^\W*snippet_name: (\w+)$/,
      data: /^\W*snippet_contents: (.+)$/,
    },

    variables: {
      name: /^\W*variable_name: (\w+)$/,
      data: /^\W*variable_data: (.+)$/,
    }
  }

  attr_accessor :site, :site_name, :resource, :base_dir, :site_dir, :input, :debug

  # Example:
  #
  #   SyncEE.prompt_user("(e)ENGLISH (s)PANISH (a)BORT" /e|s|a/)
  #
  # NB be sure to include an 'a' or similar to abort.
  #
  def self.prompt_user(prompt, regex)
    response = nil

    while response !~ regex
      STDIN.flush
      puts unless response.nil? # not the first time
      print "#{prompt} > "
      response = STDIN.getch
    end
    puts

    response
  end

  # Required site keys:
  #
  #   ssh_host    -- DNS name, IP address or "Host" entry in ~/.ssh/config
  #   db_name     -- Name of MySQL database
  #   db_user     -- User of db_name
  #   db_password -- Password of db_user
  #
  # Optional site keys:
  #
  #   ssh_user -- Login user of ssh_host (default: none)
  #   ssh_port -- Port of ssh_host (default: 22)
  #   db_host  -- Host name or IP address of db_name (default: localhost)
  #   site_id  -- ExpressionEngine Site ID (default: 1)
  #
  def initialize(site, debug = false)
    @site = site
    @debug = debug

    unless valid_site?
      puts "Here are the required arguments:\n\t#{REQUIRED_ARGS.join(', ')}\nAnd here is what you gave me:\n\t#{site.inspect}"
      exit 1
    end

    if read_site_name
      @site_name = input.strip
      puts "Synchronizing from #{site_name}"
    else
      puts "Can't read site name from #{site[:db_name]} database"
      exit 1
    end

    sync :templates
    sync :snippets
    sync :variables
  end

  private

  def valid_site?
    REQUIRED_ARGS.all?{ |key| site.keys.include?(key.to_sym) && !site[key.to_sym].empty? }
  end

  def read_site_name
    site_id = site.keys.include?(:site_id) ? site[:site_id] : 1
    sql = SQL[:site_name] % site_id

    shell_command = <<SHELL
ssh #{ssh_params} 'mysql --execute="#{sql}" --skip-column-names #{mysql_params}'
SHELL

    puts "Running #{shell_command}" if debug
    @input = `#{shell_command}`

    if $?.success?
      true

    else
      puts "Command failed: #{shell_command}"
      false

    end
  end

  def ssh_params
    ssh_user = site.keys.include?(:ssh_user) ? "-l #{site[:ssh_user]}" : ''
    ssh_port = site.keys.include?(:ssh_port) ? "-p #{site[:ssh_port]}" : ''

    "#{ssh_user} #{ssh_port} #{site[:ssh_host]}"
  end

  def mysql_params
    db_host = site.keys.include?(:db_host) ? site[:db_host] : 'localhost'

    "--host=#{db_host} --user=#{site[:db_user]} --password=#{site[:db_password]} #{site[:db_name]}"
  end

  def sync(resource)
    @resource = resource

    return unless read_resource

    if input.empty?
      puts "No #{resource} found"
      return
    end

    @base_dir = "#{Dir.pwd}/ee/#{resource}"
    @site_dir = "#{base_dir}/#{site_name}"

    archive_existing_resource
    write_resource
  end

  def read_resource
    site_id = site.keys.include?(:site_id) ? site[:site_id] : 1
    sql = SQL[resource] % site_id

    shell_command = <<SHELL
ssh #{ssh_params} 'mysql --batch --execute="#{sql}" --raw --vertical #{mysql_params}'
SHELL

    puts "Running #{shell_command}" if debug
    @input = `#{shell_command}`

    if $?.success?
      puts "Read #{input.length} bytes of #{resource}"
      dump_input if debug
      true

    else
      puts "Command failed: #{shell_command}"
      false

    end
  end

  def archive_existing_resource
    return unless File.directory? site_dir

    archive_dir = "#{base_dir}/archive/#{site_name}"
    ensure_dir archive_dir

    # archive sub-dirs are ascending postive integers
    sub_dir = Dir.entries(archive_dir).sort_by(&:to_i).last.to_i + 1
    FileUtils.mv site_dir, "#{archive_dir}/#{sub_dir}"

    puts "Moved #{site_dir} to #{archive_dir}/#{sub_dir}"
  end

  def write_resource
    ensure_dir site_dir

    name = ''
    data = []
    template_group = ''
    template_type = ''
    php_template = ''

    input.each_line do |line|
      # prevent: invalid byte sequence in utf-8
      line.force_encoding('ISO-8859-1').encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')

      if line.match(INPUT[:row])
        if !name.empty? && !data.empty?
          write_file name, data, template_group, template_type, php_template
        end

        name = ''
        data = []
        template_group = ''
        template_type = ''
        php_template = ''

      elsif match = line.match(INPUT[resource][:name])
        name = match[1]

      elsif templates? && match = line.match(INPUT[resource][:template_group])
        template_group = match[1]

      elsif templates? && match = line.match(INPUT[resource][:template_type])
        template_type = match[1]

      elsif templates? && match = line.match(INPUT[resource][:php_template])
        php_template = match[1]

      elsif match = line.match(INPUT[resource][:data])
        data << match[1]
        data << "\n" # not included in match()

      else
        data << line

      end
    end

    if !name.empty? && !data.empty?
      write_file name, data, template_group, template_type, php_template
    end
  end

  def templates?
    resource == :templates
  end

  def write_file(name, data, template_group, template_type, php_template)
      dir = dir_for template_group
      ext = ext_for template_type, php_template

      path = "#{dir}/#{name}.#{ext}"
      open(path, 'w') { |f| f.write(data.join) }

      puts "Created #{path} (#{data.join.length} bytes)"
  end

  def dir_for(template_group)
    dir = template_group.empty? ? site_dir : "#{site_dir}/#{template_group}"
    ensure_dir dir

    dir
  end

  def ext_for(template_type, php_template)
    case template_type
    when 'css', 'js', 'xml'
      template_type

    when 'webpage'
      php_template == 'y' ? 'php' : 'html'

    else
      'html'

    end
  end

  def ensure_dir(dir)
    unless File.directory? dir
      FileUtils.mkpath dir

      puts "Created #{dir}"
    end
  end

  def dump_input
    path = "#{site_name}-#{resource}.txt"
    open(path, 'w') { |f| f.write(input) }

    puts "Wrote #{input.length} bytes to #{path}"
  end
end
