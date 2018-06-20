require 'sshkit/command_sudo_ssh_forward'

module SSHKit
  module Backend
    class NetsshGlobal < Netssh
      class Configuration < Netssh::Configuration
        attr_accessor :owner, :directory, :shell
        attr_writer :ssh_commands

        def ssh_commands
          @ssh_commands ||= [:ssh, :git, :'ssh-add', :bundle]
        end
      end

      class << self
        def config
          @config ||= Configuration.new
        end
      end

      @pool = SSHKit::Backend::ConnectionPool.new

      def upload!(local, remote, options = {})
        execute :setfacl, "-m u:#{ssh_user}:rwx #{File.dirname(remote)}; true"
        execute :setfacl, "-m u:#{ssh_user}:rw #{remote}; true"
        super
        as :root do
          # Required as uploaded file is owned by SSH user, not owner
          execute :chown, property(:owner), remote
        end
      end

      private

      def user
        @user || property(:owner)
      end

      def ssh_user
        host.user || configure_host.ssh_options.fetch(:user)
      end

      def pwd
        @pwd.nil? ? property(:directory) : File.join(@pwd)
      end

      def property(name)
        host.properties.public_send(name) || self.class.config.public_send(name)
      end

      def with_ssh
        configure_host
        self.class.pool.with(
            Net::SSH.method(:start),
            String(host.hostname),
            host.username,
            host.netssh_options
        ) do |connection|
          yield connection
        end
      end

      def configure_host
        host.tap do |h|
          h.ssh_options = self.class.config.ssh_options.merge(host.ssh_options || {})
        end
      end

      def command(args, options)
        options.merge!(
          in: pwd,
          env: @env,
          host: configure_host,
          user: user,
          group: @group,
          ssh_commands: property(:ssh_commands),
          shell: property(:shell)
        )
        SSHKit::CommandSudoSshForward.new(*args.concat([options]))
      end
    end
  end
end
