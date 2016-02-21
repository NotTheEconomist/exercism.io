require 'etc'
require 'pg'

require_relative '../lib/db/config'

# We want our Docker process to use the same uid as the owner of the
# exercism repository checkout. This will ensure that any created files
# have the same owner and can be accessed on the host system, rather than
# being owned by root and hard to modify or delete.
HOST_UID = File::Stat.new('/exercism').uid

# This is just the username for the uid, for cosmetic purposes only really.
# Might as well make it match the user of the host system.
HOST_USER = ENV.fetch('HOST_USER', 'code_executor_user')

def does_username_exist(username)
  begin
    Etc.getpwnam(username)
    true
  rescue ArgumentError
    false
  end
end

def does_uid_exist(uid)
  begin
    Etc.getpwuid(uid)
    true
  rescue ArgumentError
    false
  end
end

def assume_uid
  if Process.euid != HOST_UID
    if not does_uid_exist(HOST_UID)
      username = HOST_USER
      while does_username_exist(username)
        username += '0'
      end
      home_dir = '/home/' + username
      system("useradd -d #{home_dir} -m #{username} -u #{HOST_UID}")
    end
    ENV['HOME'] = '/home/' + Etc.getpwuid(HOST_UID).name
    Process::UID.change_privilege(HOST_UID)
  end
end

def is_db_accepting_connections
  config = DB::Config.new.options
  result = PG::Connection.ping(
    :host => config['host'],
    :port => config['port'],
    :user => config['username'],
    :password => config['password'],
    :dbname => 'postgres',
    :connect_timeout => 1
  )
  result == PG::PQPING_OK
end

# Because the db container is often started at the same time as its
# dependents, a race condition exists whereby the dependents may try
# to access the db before it's ready. This function allows us the dependent
# to wait until the db is ready before proceeding.
def wait_for_db
  20.times do |n|
    puts "Waiting for db to accept connections (attempt ##{n+1})..."
    if is_db_accepting_connections
      return
    end
    sleep 0.5
  end
  Kernel.abort("Unable to connect to db.")
end

assume_uid

wait_for_db if ENV.has_key? 'DEV_DATABASE_HOST'

exec *ARGV
