module Pipe2me::Tunnel
  extend self

  # start all tunnels
  def start_all
    Procfile.write      # rebuild procfile

    puts File.read(Procfile.path)
    Kernel.exec "foreman", "start", "--procfile=#{Procfile.path}", "--root=#{File.expand_path("~")}"
  end

  def export(format)
    path = File.join(Pipe2me::Config.path, format)

    Procfile.write      # rebuild procfile

    Kernel.exec "foreman", "export", format,
      path,                                                     # the resulting config file(s)
      "--procfile=#{Procfile.path}",                            # the input procfile
      # "--root=#{Pipe2me::Config.path("foreman.root")}",       # the "app" root
      # "--app=#{Pipe2me::Config.path("foreman.app")}",         # the "app" root
      "--log=#{Pipe2me::Config.path("foreman.log")}"          # the log dir
  end

  private

  module Procfile
    extend self

    # The procfile path
    def path
      "#{Pipe2me::Config.path}/Procfile"
    end

    def write
      File.open(path, "w") do |io|
        Pipe2me::Config.tunnels.each do |name|
          entries_for(name).each do |entry|
            io.puts entry
          end
        end
      end
    end

    def entries_for(name)
      info = Pipe2me::Config.tunnel(name)

      name, ports, tunnel = info.values_at :name, :ports, :tunnel
      tunnel_uri = URI.parse(tunnel)

      # verify, and, if needed, fix id_rsa mod (too prevent (some) ssh's
      # from complaining
      id_rsa = File.join Pipe2me::Config.path("tunnels"), name, "id_rsa"
      FileUtils.chmod 0600, id_rsa

      # create a command for each port
      ports.map do |port|
        command = [
          "autossh",
          "-M 0",
          "#{tunnel_uri.user}@#{tunnel_uri.host}",
          "-p #{tunnel_uri.port}",
          "-R 0.0.0.0:#{port}:localhost:#{port}",
          "-i #{id_rsa}",
          "-o StrictHostKeyChecking=no",
          "-N"
        ]

        "#{name.split(".", 2).first}-#{port}: #{command.join(" ")}\n"
      end
    end
  end
end
