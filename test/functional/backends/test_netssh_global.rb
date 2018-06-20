require_relative '../../helper'
require 'securerandom'

require 'sshkit/backends/netssh_global'

module SSHKit
  module Backend
    class TestNetsshGlobalFunctional < FunctionalTest
      def setup
        super
        @output = String.new
        SSHKit.config.output_verbosity = :debug
        SSHKit.config.output = SSHKit::Formatter::SimpleText.new(@output)

        NetsshGlobal.configure do |config|
          config.owner = a_user
          config.directory = nil
          config.shell = nil
        end
        VagrantWrapper.reset!
      end

      def a_user
        a_box.fetch('users').fetch(0)
      end

      def another_user
        a_box.fetch('users').fetch(1)
      end

      def a_box
        VagrantWrapper.boxes_list.first
      end

      def a_host
        VagrantWrapper.hosts['one']
      end

      def test_simple_netssh
        NetsshGlobal.new(a_host) do
          execute 'date'
          execute :ls, '-l'
          with rails_env: :production do
            within '/tmp' do
              as :root do
                execute :touch, 'restart.txt'
              end
            end
          end
        end.run

        command_lines = @output.lines.select { |line| line.start_with?('Command:') }
        assert_equal [
                         "Command: sudo -u owner -- sh -c '/usr/bin/env date'\n",
                         "Command: sudo -u owner -- sh -c '/usr/bin/env ls -l'\n",
                         "Command: if test ! -d /tmp; then echo \"Directory does not exist '/tmp'\" 1>&2; false; fi\n",
                         "Command: if ! sudo -u root whoami > /dev/null; then echo \"You cannot switch to user 'root' using sudo, please check the sudoers file\" 1>&2; false; fi\n",
                         "Command: cd /tmp && sudo -u root RAILS_ENV=production -- sh -c '/usr/bin/env touch restart.txt'\n"
                     ], command_lines
      end

      def test_capture
        captured_command_result = nil
        NetsshGlobal.new(a_host) do |_host|
          captured_command_result = capture(:uname)
        end.run

        assert_includes %W(Linux Darwin), captured_command_result
      end

      def test_ssh_option_merge
        a_host.ssh_options = { paranoid: true }
        host_ssh_options = {}
        SSHKit::Backend::NetsshGlobal.config.ssh_options = { forward_agent: false }
        NetsshGlobal.new(a_host) do |host|
          capture(:uname)
          host_ssh_options = host.ssh_options
        end.run
        assert_equal [:forward_agent, :paranoid, :known_hosts, :logger, :password_prompt].sort, host_ssh_options.keys.sort
        assert_equal false, host_ssh_options[:forward_agent]
        assert_equal true, host_ssh_options[:paranoid]
        assert_instance_of SSHKit::Backend::Netssh::KnownHosts, host_ssh_options[:known_hosts]
      end

      def test_env_vars_substituion_in_subshell
        captured_command_result = nil
        NetsshGlobal.new(a_host) do |_host|
          with some_env_var: :some_value do
            captured_command_result = capture(:echo, '$SOME_ENV_VAR')
          end
        end.run
        assert_equal "some_value", captured_command_result
      end

      def test_configure_owner_via_global_config
        NetsshGlobal.configure do |config|
          config.owner = a_user
        end

        output = ''
        NetsshGlobal.new(a_host) do
          output = capture :whoami
        end.run
        assert_equal a_user, output
      end

      def test_configure_owner_via_host
        a_host.properties.owner = another_user

        output = ''
        NetsshGlobal.new(a_host) do
          output = capture :whoami
        end.run
        assert_equal another_user, output
      end

      def test_configure_shell_via_global_config
        NetsshGlobal.configure do |config|
          config.shell = "csh"
        end

        running_shell = ''
        NetsshGlobal.new(a_host) do
          running_shell = capture :echo, '$shell'
        end.run

        assert_equal '/bin/csh', running_shell
      end

      def test_configure_directory_to_nil_has_no_effect
        NetsshGlobal.configure do |config|
          config.directory = nil
        end

        output = ''
        NetsshGlobal.new(a_host) do
          output = capture :pwd
        end.run
        assert_equal "/home/#{a_host.user}", output
      end

      def test_configure_directory_via_global_config
        NetsshGlobal.configure do |config|
          config.directory = '/tmp'
        end

        output = ''
        NetsshGlobal.new(a_host) do
          output = capture :pwd
        end.run
        assert_equal '/tmp', output
      end

      def test_configure_directory_via_host
        NetsshGlobal.configure do |config|
          config.directory = '/usr'
        end

        a_host.properties.directory = '/tmp'
        output = ''
        NetsshGlobal.new(a_host) do
          output = capture :pwd
        end.run
        assert_equal '/tmp', output
      end

      def test_execute_raises_on_non_zero_exit_status_and_captures_stdout_and_stderr
        err = assert_raises SSHKit::Command::Failed do
          NetsshGlobal.new(a_host) do
            execute :echo, "\"Test capturing stderr\" 1>&2; false"
          end.run
        end
        assert_equal "echo exit status: 1\necho stdout: Nothing written\necho stderr: Test capturing stderr\n", err.message
      end

      def test_test_does_not_raise_on_non_zero_exit_status
        NetsshGlobal.new(a_host) do
          test :false
        end.run
      end

      def test_test_executes_as_owner_when_command_contains_no_spaces
        result = NetsshGlobal.new(a_host) do
          test 'test', '"$USER" = "owner"'
        end.run

        assert(result, 'Expected test to execute as "owner", but it did not')
      end

      def test_upload_file
        file_contents = ""
        file_owner = nil
        file_name = File.join("/tmp", SecureRandom.uuid)
        File.open file_name, 'w+' do |f|
          f.write 'example_file'
        end

        NetsshGlobal.new(a_host) do
          upload!(file_name, file_name)
          file_contents = capture(:cat, file_name)
          file_owner = capture(:stat, '-c', '%U',  file_name)
        end.run

        assert_equal 'example_file', file_contents
        assert_equal a_user, file_owner
      end

      def test_upload_file_to_folder_owned_by_user
        dir = File.join('/tmp', SecureRandom.uuid)
        NetsshGlobal.new(a_host) do
          execute(:mkdir, dir)
        end.run

        file_name = SecureRandom.uuid
        local_file = File.join('/tmp', file_name)
        File.open local_file, 'w+' do |f|
          f.write 'example_file'
        end

        file_contents = ""
        file_owner = nil
        remote_file = File.join(dir, file_name)
        NetsshGlobal.new(a_host) do
          upload!(local_file, remote_file)
          file_contents = capture(:cat, remote_file)
          file_owner = capture(:stat, '-c', '%U',  remote_file)
        end.run

        assert_equal 'example_file', file_contents
        assert_equal a_user, file_owner
      end

      def test_upload_file_overtop_of_existing_file
        file_name = File.join('/tmp', SecureRandom.uuid)
        File.open file_name, 'w+' do |f|
          f.write 'example_file'
        end

        NetsshGlobal.new(a_host) do
          upload!(file_name, file_name)
        end.run

        file_contents = ""
        file_owner = nil
        NetsshGlobal.new(a_host) do
          upload!(file_name, file_name)
          file_contents = capture(:cat, file_name)
          file_owner = capture(:stat, '-c', '%U',  file_name)
        end.run

        assert_equal 'example_file', file_contents
        assert_equal a_user, file_owner
      end

      def test_upload_and_then_capture_file_contents
        actual_file_contents = ""
        actual_file_owner = nil
        file_name = File.join("/tmp", SecureRandom.uuid)
        File.open file_name, 'w+' do |f|
          f.write "Some Content\nWith a newline and trailing spaces    \n "
        end
        NetsshGlobal.new(a_host) do
          upload!(file_name, file_name)
          actual_file_contents = capture(:cat, file_name, strip: false)
          actual_file_owner = capture(:stat, '-c', '%U',  file_name)
        end.run
        assert_equal "Some Content\nWith a newline and trailing spaces    \n ", actual_file_contents
        assert_equal a_user, actual_file_owner
      end

      def test_upload_within
        file_name = SecureRandom.uuid
        file_contents = "Some Content"
        dir_name = SecureRandom.uuid
        actual_file_contents = ""
        actual_file_owner = nil
        NetsshGlobal.new(a_host) do |_host|
          within("/tmp") do
            execute :mkdir, "-p", dir_name
            within(dir_name) do
              upload!(StringIO.new(file_contents), file_name)
            end
          end
          actual_file_contents = capture(:cat, "/tmp/#{dir_name}/#{file_name}", strip: false)
          actual_file_owner = capture(:stat, '-c', '%U', "/tmp/#{dir_name}/#{file_name}")
        end.run
        assert_equal file_contents, actual_file_contents
        assert_equal a_user, actual_file_owner
      end

      def test_upload_string_io
        file_contents = ""
        file_owner = nil
        NetsshGlobal.new(a_host) do
          file_name = File.join("/tmp", SecureRandom.uuid)
          upload!(StringIO.new('example_io'), file_name)
          file_contents = download!(file_name)
          file_owner = capture(:stat, '-c', '%U',  file_name)
        end.run
        assert_equal "example_io", file_contents
        assert_equal a_user, file_owner
      end

      def test_upload_large_file
        size      = 25
        fills     = SecureRandom.random_bytes(1024*1024)
        file_name = "/tmp/file-#{SecureRandom.uuid}-#{size}.txt"
        File.open(file_name, 'w') do |f|
          (size).times {f.write(fills) }
        end

        file_contents = ""
        NetsshGlobal.new(a_host) do
          upload!(file_name, file_name)
          file_contents = download!(file_name)
        end.run

        assert_equal File.open(file_name).read, file_contents
      end

      def test_upload_via_pathname
        file_contents = ""
        file_owner = nil
        NetsshGlobal.new(a_host) do |_host|
          file_name = Pathname.new(File.join("/tmp", SecureRandom.uuid))
          upload!(StringIO.new('example_io'), file_name)
          file_owner = capture(:stat, '-c', '%U',  file_name)
          file_contents = download!(file_name)
        end.run
        assert_equal "example_io", file_contents
        assert_equal a_user, file_owner
      end

      def test_interaction_handler
        captured_command_result = nil
        NetsshGlobal.new(a_host) do
          command = 'echo Enter Data; read the_data; echo Captured $the_data;'
          captured_command_result = capture(command, interaction_handler: {
              "Enter Data\n" => "SOME DATA\n",
              "Captured SOME DATA\n" => nil
          })
        end.run
        assert_equal("Enter Data\nCaptured SOME DATA", captured_command_result)
      end

      def test_ssh_forwarded_when_command_is_ssh_command
        remote_ssh_output = ''
        local_ssh_output = `ssh-add -l 2>&1`.strip
        a_host.ssh_options = { forward_agent: true }
        NetsshGlobal.new(a_host) do |host|
          remote_ssh_output = capture 'ssh-add', '-l', '2>&1;', 'true'
        end.run

        assert_equal local_ssh_output, remote_ssh_output
      end

      def test_ssh_not_forwarded_when_command_is_not_an_ssh_command
        echo_output = ''

        a_host.ssh_options = { forward_agent: true }
        a_host.properties.ssh_commands = [:not_echo]
        NetsshGlobal.new(a_host) do |host|
          echo_output = capture :echo, '$SSH_AUTH_SOCK'
        end.run

        assert_match '', echo_output
      end

      def test_can_configure_ssh_commands
        echo_output = ''

        a_host.ssh_options = { forward_agent: true }
        a_host.properties.ssh_commands = [:echo]
        NetsshGlobal.new(a_host) do |host|
          echo_output = capture :echo, '$SSH_AUTH_SOCK'
        end.run

        assert_match /\/tmp\//, echo_output
      end

      def test_default_ssh_commands
        ssh_commands = NetsshGlobal.config.ssh_commands

        assert_equal [:ssh, :git, :'ssh-add', :bundle], ssh_commands
      end
    end
  end
end
