require "sshd"

SSHD.root = File.join( "#{VAR}/sshd")
SSHD.listen_address = "#{TUNNEL_DOMAIN}:#{SSHD_PORT}"
