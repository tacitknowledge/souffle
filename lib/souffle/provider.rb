require 'fileutils'
require 'tmpdir'

# A metal provider module (Describes AWS, Softlayer, etc).
module Souffle::Provider
  class << self
    # Returns the list of available provider plugins.
    #
    # @return [ Array ] The list of available provider plugins.
    def plugins
      constants.map { |k| k.to_s.downcase }
    end

    # Returns the plugin with the given name.
    #
    # @param [ String ] name The name of the plugin to select.
    #
    # @return [ Souffle::Provider::Base ] The plugin with the given name.
    def plugin(name)
      plug = constants.select { |k| k.to_s.downcase == name.downcase }.first
      Souffle::Provider.const_get(plug)
    rescue Souffle::Exceptions::PluginDoesNotExist => e
      Souffle::Log.error "#{e.message}:\n#{e.backtrace.join("\n")}"
    end
  end

  # The souffle cloud provider class.
  class Base
    attr_accessor :system

    # Initialize a new provider for a given system.
    #
    # @param [ Souffle::System ] system The system to provision.
    def initialize(system=Souffle::System.new)
      @system ||= system
      #create_ssh_dir_if_missing
    end

    # The name of the given provider.
    #
    # @return [ String ] The name of the given provider.
    def name
      self.class.name.split('::').last
    end

    # Wait until ssh is available for the node and then connect.
    def boot(node)
    end

    # Creates a system for a given provider. Intended to be overridden.
    #
    # @raise [Souffle::Exceptions::Provider] This definition must be
    # overrridden.
    #
    # @param [ Souffle::System ] system The system to instantiate.
    # @param [ String ] tag The tag to use for the system.
    def create_system(system, tag=nil)
      error_msg = "#{self.class.to_s}: you must override create_system"
      raise Souffle::Exceptions::Provider, error_msg
    end

    # Takes a node definition and begins the provisioning process.
    #
    # @param [ Souffle::Node ] node The node to instantiate.
    # @param [ String ] tag The tag to use for the node.
    def create_node(node, tag=nil)
      error_msg = "#{self.class.to_s}: you must override create_node"
      raise Souffle::Exceptions::Provider, error_msg
    end

    # Creates a raid array for a given provider. Intended to be overridden.
    #
    # @raise [Souffle::Exceptions::Provider] This definition must be
    # overridden.
    def create_raid
      error_msg = "#{self.class.to_s}: you must override create_raid"
      raise Souffle::Exceptions::Provider, error_msg
    end

    # Generates the json required for chef-solo to run on a node.
    #
    # @param [ Souffle::Node ] node The node to generate chef-solo json for.
    #
    # @return [ String ] The chef-solo json for the particular node.
    def generate_chef_json(node)
      json_info = Hash.new
      json_info[:domain] = node.try_opt(:domain) || "souffle"
      json_info.merge!(node.options[:attributes])
      json_info[:run_list] = node.run_list
      JSON.pretty_generate(json_info)
    end

    # Waits for ssh to be accessible for a node for the initial connection and
    # yields an ssh object to manage the commands naturally from there.
    #
    # @param [ String ] address The address of the machine to connect to.
    # @param [ String ] user The user to connect as.
    # @param [ String, NilClass ] pass By default publickey and password auth
    # will be attempted.
    # @param [ Hash ] opts The options hash.
    # @param [ Fixnum ] timeout The timeout for ssh boot.
    # @option opts [ Hash ] :net_ssh Options to pass to Net::SSH,
    # see Net::SSH.start
    # @option opts [ Hash ] :timeout (TIMEOUT) default timeout for all
    # #wait_for and #send_wait calls.
    # @option opts [ Boolean ] :reconnect When disconnected reconnect.
    #
    # @yield [ Eventmachine::Ssh:Session ] The ssh session.
    def wait_for_boot(address, user="root", pass=nil, opts={},
                      timeout=200)
      Souffle::Log.info "Waiting for ssh for #{address}..."
      is_booted = false
      timer = EM::PeriodicTimer.new(EM::Ssh::Connection::TIMEOUT) do
        opts[:password] = pass unless pass.nil?
        opts[:paranoid] = false
        EM::Ssh.start(address, user, opts) do |connection|
          connection.errback  { |err| nil }
          connection.callback do |ssh|
            is_booted = true
            yield(ssh) if block_given?
            ssh.close
          end
        end
      end

      EM::Timer.new(timeout) do
        unless is_booted
          Souffle::Log.error "SSH Boot timeout for #{address}..."
          timer.cancel
        end
      end
    end

    # Yields an ssh object to manage the commands naturally from there.
    #
    # @param [ String ] address The address of the machine to connect to.
    # @param [ String ] user The user to connect as.
    # @param [ String, NilClass ] pass By default publickey and password auth
    # will be attempted.
    # @param [ Hash ] opts The options hash.
    # @option opts [ Hash ] :net_ssh Options to pass to Net::SSH,
    # see Net::SSH.start
    # @option opts [ Hash ] :timeout (TIMEOUT) default timeout for all
    # #wait_for and #send_wait calls.
    # @option opts [ Boolean ] :reconnect When disconnected reconnect.
    #
    # @yield [ EventMachine::Ssh::Session ] The ssh session.
    def ssh_block(address, user="root", pass=nil, opts={}, attempt=0)
      max_attempts = 3
      opts[:password] = pass unless pass.nil?
      opts[:paranoid] = false
      connected = false
      until(connected)
        EM::Ssh.start(address, user, opts) do |connection|
          connection.errback do |err|
            Souffle::Log.info "#{opts} Failed attempt to ssh: #{attempt}"
            Souffle::Log.info "SSH_BLOCK USER #{user} PASS #{pass} IP #{address} OPTS #{opts}"
            Souffle::Log.error "#{opts} SSH Error: #{err} (#{err.class}) "
            if(attempt == max_attempts)
              Souffle::Log.error "[#{node.tag}] System Creation Failure."
              @system.nodes.each do |n|
                n.system.provisioner.creation_halted
              end
            end
            attempt+=1
            sleep 10
          end
          connection.callback { |ssh| yield(ssh) if block_given?; ssh.close; connected=true }
        end
      end
    end

    # The path to the ssh key with the given name.
    #
    # @param [ String ] key_name The name fo the ssh key to lookup.
    #
    # @return [ String ] The path to the ssh key with the given name.
    def ssh_key(key_name)
      "#{ssh_key_path}/#{key_name}"
    end

    # Grabs an ssh key for a given aws node.
    #
    # @param [ String ] key_name The name fo the ssh key to lookup.
    #
    # @return [ Boolean ] Whether or not the ssh_key exists
    # for the node.
    def ssh_key_exists?(key_name)
      File.exists? ssh_key(key_name)
    end

    # Creates the ssh directory for a given provider if it does not exist.
    def create_ssh_dir_if_missing
      FileUtils.mkdir_p(ssh_key_path) unless Dir.exists?(ssh_key_path)
    rescue
      error_msg =  "The ssh key directory does not have write permissions: "
      error_msg << ssh_key_path
      raise Souffle::Exceptions::PermissionErrorSshKeys, error_msg
    end

    # The path to the ssh keys for the provider.
    #
    # @return [ String ] The path to the ssh keys for the provider.
    def ssh_key_path
      File.join(File.dirname(
        Souffle::Config[:config_file]), "ssh", name.downcase)
    end

    # Rsync's a file to a remote node.
    #
    # @param [ String ] ipaddress The ipaddress of the node to connect to.
    # @param [ String ] file The file to rsync.
    # @param [ String ] path The remote path to rsync.
    def rsync_file(ipaddress, file, path='.')
      ssh_command =  "ssh -o UserKnownHostsFile=/dev/null "
      ssh_command << "-o StrictHostKeyChecking=no -o LogLevel=quiet"
      rsync_command =  "rsync -qar -e \"#{ssh_command}\" "
      rsync_command << "#{file} root@#{ipaddress}:#{path}"
      if EM.reactor_running?
        EM.system(rsync_command)
      else
        IO.popen(rsync_command)
      end
    end

    # The list of cookbooks and their full paths.
    #
    # @return [ Array ] The list of cookbooks and their full paths.
    def cookbook_paths
      Array(Souffle::Config[:chef_cookbook_path]).inject([]) do |_paths, path|
        Dir.glob("#{File.expand_path(path)}/*").each do |cb|
          _paths << cb if File.directory? cb
        end
        _paths
      end
    end

    # The list of roles and their full paths.
    #
    # @return [ Array ] The list of roles and their full paths.
    def role_paths
      Array(Souffle::Config[:chef_role_path]).inject([]) do |_paths, path|
        Dir.glob("#{File.expand_path(path)}/*").each do |role|
          _paths << role if role[-3..-1].eql?(".rb")
        end
        _paths
      end
    end

    # Creates a new cookbook tarball for the deployment.
    #
    # @return [ String ] The path to the created tarball.
    def create_cookbooks_tarball
      tarball_name = "cookbooks-latest.tar.gz"
      temp_dir = File.join(Dir.tmpdir, "chef-cookbooks-latest")
      temp_cookbook_dir = File.join(temp_dir, "cookbooks")
      temp_roles_dir = File.join(temp_dir, "roles")
      tarball_dir = "#{File.dirname(Souffle::Config[:config_file])}/tarballs"
      tarball_path = File.join(tarball_dir, tarball_name)

      FileUtils.mkdir_p(tarball_dir) unless File.exists?(tarball_dir)
      FileUtils.mkdir_p(temp_dir) unless File.exists?(temp_dir)
      FileUtils.mkdir(temp_cookbook_dir) unless File.exists?(temp_cookbook_dir)
      FileUtils.mkdir(temp_roles_dir) unless File.exists?(temp_roles_dir)
      cookbook_paths.each { |pkg| FileUtils.cp_r(pkg, temp_cookbook_dir) }
      role_paths.each { |role| FileUtils.cp(role, temp_roles_dir) }

      tar_command =  "tar -C #{temp_dir} -czf #{tarball_path} "
      tar_command << "./cookbooks ./roles"
      if EM.reactor_running?
        EM::DeferrableChildProcess.open(tar_command) do
          FileUtils.rm_rf temp_dir
        end
      else
        Kernel.system(tar_command)
        FileUtils.rm_rf temp_dir
      end
      tarball_path
    end

    class << self
      # Updates the souffle status with the latest provider information.
      def update_status; end
    end

  end
end

_provider_dir = File.join(File.dirname(__FILE__), "provider")
Dir.glob("#{_provider_dir}/*").each do |s|
  require "souffle/provider/#{File.basename(s)}"
end
