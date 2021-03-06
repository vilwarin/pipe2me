require "sys"
require "digest/sha1"

class Tunnel < ActiveRecord::Base
end

require_relative "tunnel/fqdn"
require_relative "tunnel/port"
require_relative "tunnel/check"
require_relative "tunnel/token"
require_relative "tunnel/status"

#
# A Tunnel object models a single tunnel registration. Each tunnel
# manages a number of ports. These ports are assigned by the server in the
# TUNNEL_PORTS range. Tunnel manages a number of tunnels on different ports.
#
# The request for a tunnel contains a number of services, like http,
# https, etc. These service settings are used to determine whether the
# service running on the machine tunnelled to is alive, and whether all
# services are accessible directly - which allows to redirect traffic to
# that machine via DNS. These settings are returned by the *ports* attribute.
#
# The tunnel has openssh identity tokens in *ssh_public_key* and
# *ssh_private_key*, which can be used to establish the tunnels via OpenSSH,
# and an OpenSSL certificate in *openssl_certificate*.

# Other attributes:
#
# - a tunnel is identified by a *token* - a randomly generated string.
# - a tunnel has a *fqdn*
# - a tunnel has a tunnel *endpoint*. This is the hostname which offers
#   the publicly available ports for the services.
# - a tunnel has a ssl identity in *ssh_public_key*. This is generated by
#   the client and submitted during tunnel setup.
# - a tunnel has an *openssl_certificate*. This is generated by
#   the client and submitted during tunnel setup. The server signs it and
#   sends it back to the client, but also keeps it for reference purposes.
#
class Tunnel < ActiveRecord::Base
  SELF = self

  # -- include modules --------------------------------------------------------

  include Token, Status

  # -- name and port are readonly, once chosen, and are set automatically -----

  attr_readonly :fqdn, :protocols

  validates_uniqueness_of :fqdn, :on => :create
  validates_presence_of   :fqdn, :on => :create

  # -- the target host --------------------------------------------------------

  # This is the tunnel target hostname. This entry is useful to define
  # different tunnel targets based on some criteria, e.g. the region.

  # -- set default values -----------------------------------------------------

  before_validation :initialize_defaults

  def initialize_defaults
    # randomly choose ID
    self.id = SecureRandom.random_number(1 << 63) unless id?

    # generate fqdn from id
    self.fqdn = FQDN.generate(self.id) unless fqdn?
  end

  # -- ports ------------------------------------------------------------------

  attr :protocols, true

  has_many :ports, :class_name => "::Tunnel::Port", :dependent => :destroy

  # Note: assign_ports must be run after the tunnel is created! Otherwise
  # when a newly assigned ports gets assigned to this tunnel it gets not
  # marked as assigned (by setting its tunnel_id) and will be reassigned
  # for the next protocol.
  after_create :assign_ports

  # The protocols attribute contains a list of protocols.
  def assign_ports
    protocols = self.protocols || []
    return if protocols.empty?

    Port.reserve! protocols.count

    protocols.each do |protocol|
      port = Port.unused.first
      raise "Cannot reserve port for '#{protocol}' protocol" unless port
      port.update_attributes! protocol: protocol
      self.ports << port
    end
  end

  # -- check ------------------------------------------------------------------

  has_many :checks, :class_name => "::Tunnel::Check", :dependent => :destroy

  # [todo] - implement a check whether or not the tunnel is online.
  # [todo] - run check! in the background
  def check!(options = {})
    # expect! options => { source_ip: String }
    status = ports.all? do |port|
      port.available? options[:source_ip]
    end

    checks.create!(source_ip: options[:source_ip], status: status ? "online" : "offline")
  end

  # -- dynamic attributes -----------------------------------------------------

  def urls(protocol = nil)
    ports = self.ports
    ports = ports.where(protocol: protocol) if protocol
    ports.map(&:url)
  end

  # The private tunnel URL. This is where the client connects to, usually via
  # autossh, to start the tunnel(s).

  def tunnel_private_url
    "ssh://#{SSHD.user}@#{SSHD.listen_address}"
  end

  # -- OpenSSL cerificate -----------------------------------------------------

  def openssl_sign_certificate!(csr)
    tmpfile = Tempfile.new("#{fqdn}.csr")
    tmpfile.write csr
    tmpfile.close

    Sys.sys! "#{ROOT}/ca/sign-certificate", fqdn, tmpfile.path
    openssl_certificate = File.read "#{VAR}/openssl/certs/#{fqdn}.pem"
    update_attributes! :openssl_certificate => openssl_certificate

    tmpfile.unlink                            # deletes the temp file
  rescue
    tmpfile.close! rescue nil                 # close and deletes the temp file
    raise
  end

  # -- SSH keys ---------------------------------------------------------------

  def add_ssh_key(ssh_public_key)
    update_attributes! :ssh_public_key => ssh_public_key
    SSHD.write_authorized_keys
  end

  # [todo] - implement a method to kill current connections once the tunnel becomes invalid.
  def kill_connections
  end
end

module Tunnel::Etest
  def tunnel(options = {})
    options[:token] = "test@pipe2me" unless options.key?(:token)

    tunnel = Tunnel.create! options
    Tunnel.find(tunnel.id)
  end

  def test_single_protocol
    tunnel = self.tunnel protocols: %w(http)
    assert_equal(tunnel.ports.count, 1)
  end

  def test_multiple_protocols
    tunnel = self.tunnel protocols: %w(http https)
    assert_equal(tunnel.ports.count, 2)

    url_protocols = tunnel.urls.map { |url| URI.parse(url).scheme }
    assert_equal(url_protocols, %w(http https) )
  end

  def test_tunnel_check
    tunnel = self.tunnel protocols: %w(http https)
    tunnel.check! source_ip: "127.0.0.1"
  end
end
