#!/usr/bin/env ruby

require './lib/syncee.rb'

# Required parameters:
#   ssh_host    -- DNS name, IP address or "Host" entry in ~/.ssh/config
#   db_name     -- Name of MySQL database
#   db_user     -- User of db_name
#   db_password -- Password of db_user

# Optional parameters:
#   ssh_user -- Login user of ssh_host (default: none)
#   ssh_port -- Port of ssh_host (default: 22)
#   db_host  -- Host name or IP address of db_name (default: localhost)
#   site_id  -- ExpressionEngine Site ID (default: 1)

sites = {
  en: {
    ssh_host: 'example.com',
#   ssh_user: 'alice',
#   ssh_port: '22022',
#   db_host: 'mysql.example.com',
    db_name: 'ee',
    db_user: 'bob',
    db_password: 'secret',
  },

  es: {
    ssh_host: 'example.com',
#   ssh_user: 'alice',
#   ssh_port: '22022',
#   db_host: 'mysql.example.com',
    db_name: 'ee',
    db_user: 'bob',
    db_password: 'secret',
    site_id: '2',
  },
}

case SyncEE.prompt_user("example.com (e)NGLISH (s)PANISH (q)UIT", /e|s|q/)
when 'e'
  SyncEE.new sites[:en]

when 's'
  SyncEE.new sites[:es]
end

