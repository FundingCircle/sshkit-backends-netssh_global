require 'rubygems'
require 'bundler/setup'

require 'turn'
require 'minitest/unit'
require 'mocha/setup'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

Dir[File.expand_path('test/support/*.rb')].each { |file| require file }

class UnitTest < MiniTest::Unit::TestCase
  # def setup
  #   SSHKit.reset_configuration!
  # end
end

class FunctionalTest < MiniTest::Unit::TestCase
  def setup
    unless VagrantWrapper.running?
      skip "Vagrant VMs are not running. Please, start it manually with `vagrant up`"
    end
  end
end

#
# Force colours in Autotest
#
Turn.config.ansi = true
Turn.config.format = :pretty

MiniTest::Unit.autorun
