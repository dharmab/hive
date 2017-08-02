# vim: set ft=ruby :

require 'fileutils'

required_plugins = %w(vagrant-ignition)
plugins_to_install = required_plugins.select { |plugin| not Vagrant.has_plugin? plugin }
if not plugins_to_install.empty?
  puts "Installing plugins: #{plugins_to_install.join(' ')}"
  if system "vagrant plugin install #{plugins_to_install.join(' ')}"
    exec "vagrant #{ARGV.join(' ')}"
  else
    abort "Installation of one or more plugins has failed. Aborting."
  end
end

Vagrant.configure("2") do |config|
  config.vm.box = "coreos-alpha"
  config.vm.box_url = "https://alpha.release.core-os.net/amd64-usr/current/coreos_production_vagrant_virtualbox.json"

  config.ignition.enabled = true
  config.ignition.path = 'ignition.json'

  config.ssh.username = 'core'

  config.vm.provider :virtualbox do |vbox|
    vbox.check_guest_additions = false
    vbox.functional_vboxsf = false
    config.ignition.config_obj = vbox
  end

end
