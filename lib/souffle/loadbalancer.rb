require 'fileutils'

# Souffle's LoadBalancer provider
module Souffle::LoadBalancer
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
    # @return [ Souffle::LoadBalancer::Base ] The plugin with the given name.
    def plugin(name)
      plug = constants.select { |k| k.to_s.downcase == name.downcase }.first
      Souffle::DNS.const_get(plug)
    rescue Souffle::Exceptions::PluginDoesNotExist => e
      Souffle::Log.error "#{e.message}:\n#{e.backtrace.join("\n")}"
    end
  end
  
  class Base
    attr_accessor :system

    # Initialize a new LoadBalancer provider for a given system.
    #
    # @param [ Souffle::System ] system The system to provision.
    def initialize(system=Souffle::System.new)
      @system ||= system
    end
    
    def create_entry(node, ip)
    end
    
    def remove_entry(node)
    end
  end
end

_provider_dir = File.join(File.dirname(__FILE__), "loadbalancer")
Dir.glob("#{_provider_dir}/*").each do |s|
  require "souffle/loadbalancer/#{File.basename(s)}"
end