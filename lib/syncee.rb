#!/usr/bin/env ruby

# WHAT: Synchronize snippets, templates and global variables from an ExpressionEngine site to:
#
#     ./ee/snippets
#     ./ee/templates
#     ./ee/variables
#
# HOW: Create a script. For example:
# 
#   #
#   # Require this file.
#   #
#
#   require '~/lib/syncee.rb'
#
#   #
#   # Details of one or more EE sites accessible via SSH.
#   #
#
#   sites = {
#
#     en: {
#       host: 'example.com',
#       os_user: 'user',
#       db_name: 'db',
#       db_user: 'user',
#       db_password: 'pass',
#       site_id: '1',
#       site_name: 'default_site',
#     },
#
#     es: {
#       host: 'example.com',
#       os_user: 'user',
#       db_name: 'db',
#       db_user: 'user',
#       db_password: 'pass',
#       site_id: '2',
#       site_name: 'es',
#     },
#
#   }
#   
#   #
#   # Menu to provide syncing from a choice of multiple sites.
#   #
#   # Be sure to include an 'a' (or similar) to abort.
#   #
#
#   case SyncEE.prompt_user("Example.com (e)ENGLISH (s)PANISH (a)BORT", /e|s|a/)
#
#     when 'e'
#       SyncEE.new sites[:en]
#
#     when 's'
#       SyncEE.new sites[:es]
#
#   end

require 'fileutils'
require 'io/console' # STDIN.getch

class SyncEE
  SITE_KEYS = %w(host os_user db_name db_user db_password site_id site_name)

  SQL = {
    snippets: 'SELECT snippet_name, snippet_contents FROM exp_snippets WHERE site_id = %d',
    templates: 'SELECT g.group_name, t.template_name, t.template_type, t.allow_php, t.template_data FROM exp_templates t INNER JOIN exp_template_groups g USING (group_id) WHERE t.site_id = %d',
    variables: 'SELECT variable_name, variable_data FROM exp_global_variables WHERE site_id = %d'
  }

  RE = {
    snippets: {
      row: /^\*{10,} \d+\. row \*{10,}$/,
      name: /^\W*snippet_name: (\w+)$/,
      data: /^\W*snippet_contents: (.+)$/,
    },
    templates: {
      row: /^\*{10,} \d+\. row \*{10,}$/,
      name: /^\W*template_name: (\w+)$/,
      template_group: /^\W*group_name: (\w+)$/,
      template_type: /^\W*template_type: (\w+)$/,
      php_template: /^\W*allow_php: (\w+)$/,
      data: /^\W*template_data: (.+)$/,
    },
    variables: {
      row: /^\*{10,} \d+\. row \*{10,}$/,
      name: /^\W*variable_name: (\w+)$/,
      data: /^\W*variable_data: (.+)$/,
    }
  }

  MYSQL_OPTIONS = '--batch --raw --vertical'

  attr_accessor :site, :resource, :base_dir, :site_dir, :input, :debug

  def self.prompt_user(message, regex)
    response = nil
    while response !~ regex
      STDIN.flush
      print "\n" unless response.nil? # not the first time
      print "#{message} > "
      response = STDIN.getch
    end
    puts
    response
  end

  def initialize(site, debug = false)
    @site = site
    @debug = debug

    raise RuntimeError, 'site argument is invalid' unless valid_site?

    sync 'snippets'
    sync 'templates'
    sync 'variables'
  end

  private

  def valid_site?
    SITE_KEYS.all?{ |key| !site[key.to_sym].empty? }
  end

  def sync(resource)
    @resource = resource

    return unless read_resource

    if input.empty?
      puts "No #{resource} found"
      return
    end

    @base_dir = "#{Dir.pwd}/ee/#{resource}"
    @site_dir = "#{base_dir}/#{site[:site_name]}"

    archive_existing_resource
    write_resource
  end

  def read_resource
    sql = SQL[resource.to_sym] % site[:site_id]
    credentials = "--user=#{site[:db_user]} --password=#{site[:db_password]}"
    shell_command = <<SHELL
ssh #{site[:os_user]}@#{site[:host]} 'mysql --execute="#{sql}" #{credentials} #{MYSQL_OPTIONS} #{site[:db_name]}'
SHELL

    puts "Running #{shell_command}" if debug
    @input = `#{shell_command}`

    if $?.success?
      puts "Found #{input.length} bytes of #{resource}"
      dump_input if debug
      true
    else
      puts "Command failed: #{shell_command}"
      false
    end
  end

  def archive_existing_resource
    archive_dir = "#{base_dir}/archive/#{site[:site_name]}"

    unless File.directory? archive_dir
      FileUtils.mkpath archive_dir
      puts "Created #{archive_dir}"
    end

    if File.directory? site_dir
      archive = Dir.entries(archive_dir).sort_by(&:to_i).last.to_i + 1
      FileUtils.mv site_dir, "#{archive_dir}/#{archive}"
      puts "Moved #{site_dir} to #{archive_dir}/#{archive}"
    end
  end

  def write_resource
    FileUtils.mkpath site_dir
    puts "Created #{site_dir}"

    name = ''
    template_group = ''
    template_type = ''
    php_template = ''
    contents = []
    re = RE[resource.to_sym]

    input.each_line do |line|
      # invalid byte sequence in utf-8
      line.force_encoding('ISO-8859-1').encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      if line.match(re[:row])
        if !name.empty? && !contents.empty?
          write_file name, contents, template_group, template_type, php_template
        end
        name = ''
        template_group = ''
        template_type = ''
        php_template = ''
        contents = []
      elsif match = line.match(re[:name])
        name = match[1]
      elsif templates? && match = line.match(re[:template_group])
        template_group = match[1]
      elsif templates? && match = line.match(re[:template_type])
        template_type = match[1]
      elsif templates? && match = line.match(re[:php_template])
        php_template = match[1]
      elsif match = line.match(re[:data])
        contents << match[1]
        contents << "\n" # not included in match()
      else
        contents << line
      end
    end

    if !name.empty? && !contents.empty?
      write_file name, contents, template_group, template_type, php_template
    end
  end

  def templates?
    resource == 'templates'
  end

  def file_path_for(name, template_group, template_type, php_template)
    dir = template_group.length > 0 ? "#{site_dir}/#{template_group}" : site_dir
    unless File.directory? dir
      FileUtils.mkpath dir
      puts "Created #{dir}"
    end
    ext = file_extension_for template_type, php_template
    "#{dir}/#{name}.#{ext}"
  end

  def file_extension_for(template_type, php_template)
    case template_type
    when 'css'
      'css'
    when 'js'
      'js'
    when 'xml'
      'xml'
    when 'webpage'
      php_template == 'y' ? 'php' : 'html'
    else
      'html'
    end
  end

  def write_file(name, contents, template_group, template_type, php_template)
      file = file_path_for name, template_group, template_type, php_template
      open(file, 'w') { |f| f.write(contents.join) }
      puts "Created #{file} (#{contents.length} bytes)"
  end

  def dump_input
    dump = "#{site[:site_name]}-#{resource}.txt"
    open(dump, 'w') { |f| f.write(input) }
    puts "Wrote #{input.length} bytes to #{dump}"
  end
end
