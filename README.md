# SSHKit Backends Netssh Global

**SSHKit Backends Netssh Global** is a backend to be used in conjunction with
Capistrano 3 and SSHKit to allow global configuration to be set. For example, 
all commands can be run under a different user or folder - without modifying the
command.

This is designed to make it possible for Capistrano 3 to deploy on systems where
users login as one identity and then need to sudo to a different identity for
each command.

This works globally so that default tasks will automatically `sudo` and `cd`
without modification. This allows the default tasks to be used in this kind of
setup without them being altered.

If a task specifically `sudo`'s or `cd`'s then the global setting will not take
effect.

In some setups the ssh agent also needs to be forwarded (such as git clone).
Here the setting `ssh_commands` can be set to automatically forward the ssh
agent to the sudo user for certain commands.

### To run tests

To setup an OSX machine to run the tests, install Homebrew then:

```
brew tap Homebrew/bundle
brew bundle
vagrant up --provision
bundle
rake
```

### Usage

```ruby
require 'sshkit/backends/netssh_global'

set :sshkit_backend, SSHKit::Backend::NetsshGlobal

SSHKit::Backend::NetsshGlobal.configure do |config|
  config.owner        = 'bob'       # Which user to sudo as for every command
  config.directory    = '/home/bob' # Can be specified if it is important to default commands to run in a 
                                    # certain directory. This can be used to overcome permission problems when
                                    # sudo'ing
  config.ssh_commands = [:git]      # Setting for which commands require SSH forwarding
  config.shell        = 'bash -l'   # Setting that allows the shell that sudo runs to be overriden
end

# Per host configuration
Host.new("example.com").tap do |h|
  h.properties.owner        = 'fred'
  h.properties.directory    = '/home/fred'
  h.properties.ssh_commands = [:git, :bundle]
end
```

### Credits

The code and test suite are built on top of [SSHKit](http://github.com/capistrano/sshkit).
