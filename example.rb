#!/usr/bin/env ruby

require 'syncee.rb'

sites = {
  en: {
    host: 'example.com',
    os_user: 'ssh-user',
    db_name: 'database',
    db_user: 'user',
    db_password: 'password',
    site_id: '1',
    site_name: 'default_site',
  },
}

case SyncEE.prompt_user("Example.com (e)NGLISH (q)UIT", /e|q/)
  when 'e'
    SyncEE.new sites[:en]
end

