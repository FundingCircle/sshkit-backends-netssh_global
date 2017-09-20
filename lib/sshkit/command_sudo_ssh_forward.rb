module SSHKit
  class CommandSudoSshForward < SSHKit::Command
    def to_command
      return command.to_s unless should_map?

      within do
        ssh_agent do
          umask do
            with do
              user do
                in_background do
                  group do
                    to_s
                  end
                end
              end
            end
          end
        end
      end
    end

    def environment_string
      environment_hash.collect do |key,value|
        if key.is_a? Symbol
          "#{key.to_s.upcase}=#{value}"
        else
          "#{key.to_s}=#{value}"
        end
      end.join(' ')
    end

    def environment_hash
      default_env.merge(options_env)
    end

    def ssh_agent(&block)
      return yield unless ssh_forwarding_required?
      "setfacl -m #{options[:user]}:x $(dirname $SSH_AUTH_SOCK) && setfacl -m #{options[:user]}:rw $SSH_AUTH_SOCK && %s" % yield
    end

    def user(&block)
      return yield unless options[:user]
      shell = options[:shell] || 'sh'
      "sudo -u #{options[:user]} #{environment_string + " " unless environment_string.empty?}-- #{shell} -c '%s'" % %Q{#{yield}}
    end

    def with(&block)
      return yield if environment_hash.empty? || sudo_command?
      "( #{environment_string} %s )" % yield
    end

    private

    def options_env
      (options[:env] || {}).merge(default_ssh_options)
    end

    def default_env
      SSHKit.config.default_env || {}
    end

    def default_ssh_options
      ssh_forwarding_required? ? {'SSH_AUTH_SOCK' => '$SSH_AUTH_SOCK'} : {}
    end

    def ssh_forwarding_required?
       ssh_command? && sudo_command? && ssh_forwarding_enabled?
    end

    def ssh_command?
      options.fetch(:ssh_commands, []).include?(command.to_sym)
    end

    def ssh_forwarding_enabled?
      options[:host] && options[:host].ssh_options[:forward_agent]
    end

    def sudo_command?
      options[:user]
    end

  end
end
