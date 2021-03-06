# Starts up the base provisioner class with system and node state machines.
class Souffle::Provisioner; end

require 'souffle/provisioner/node'
require 'souffle/provisioner/system'

# Starts up the base provisioner class with system and node state machines.
class Souffle::Provisioner
  attr_reader :provider, :system

  # Creates a new provisioner.
  def initialize
    @provider = initialize_provider
    @provisioner = nil
  end

  # Creates the system object from a hash.
  # 
  # @param [ Hash ] system_hash The system represented in hash format.
  def setup_system(system_hash)
    @system = Souffle::System.from_hash(system_hash)
    @provider = initialize_provider(
      cleanup_provider(@system.try_opt[:provider]))
  end

  # Cleans up the provider name to match the providers we have.
  # 
  # @param [ String ] provider The name of the provider to use.
  # 
  # @return [ String ] The cleaned up provider name.
  def cleanup_provider(provider)
    lookups = {}
    Souffle::Provider.constants.each { |k| lookups[k.to_s.downcase] = k.to_s }
    lookups.fetch([provider.downcase], provider)
  end

  # Sets up the given provider to be used for the creation of a system.
  # 
  # @param [ String ] provider The system provider to use for provisioning.
  def initialize_provider(provider=nil)
    prv = cleanup_provider(Souffle::Config[:provider])
    Souffle::Provider.const_get(prv).new
  rescue Souffle::Exceptions::InvalidAwsKeys => e
    Souffle::Log.error "#{e.message}:\n#{e.backtrace.join("\n")}"
  rescue Exception
    raise Souffle::Exceptions::InvalidProvider,
      "The provider Souffle::Provider::#{prv} does not exist."
  end

  # Starts the provisioning process keeping a local lookup to the provisioner.
  def begin_provisioning
    @provisioner = Souffle::Provisioner::System.new(@system, @provider)
  end
  
end
