require_relative '../../helper'
require 'securerandom'

require 'sshkit/backends/netssh_global'

module SSHKit
  module Backend
    class TestNetsshGlobalFunctional < FunctionalTest
      def setup
        super
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

      def test_capture
        File.open('/dev/null', 'w') do |dnull|
          SSHKit.capture_output(dnull) do
            captured_command_result = nil
            NetsshGlobal.new(a_host) do
              captured_command_result = capture(:uname)
            end.run

            assert captured_command_result
            assert_match captured_command_result, /Linux|Darwin/
          end
        end
      end

      def test_ssh_option_merge
        a_host.ssh_options = { paranoid: true }
        host_ssh_options = {}
        SSHKit::Backend::NetsshGlobal.config.ssh_options = { forward_agent: false }
        NetsshGlobal.new(a_host) do |host|
          capture(:uname)
          host_ssh_options = host.ssh_options
        end.run
        assert_equal({ forward_agent: false, paranoid: true }, host_ssh_options)
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

      def test_test_executes_as_ssh_user_when_command_contains_spaces
        result = NetsshGlobal.new(a_host) do
          test 'test "$USER" = "vagrant"'
        end.run

        assert(result, 'Expected test to execute as "vagrant", but it did not')
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
