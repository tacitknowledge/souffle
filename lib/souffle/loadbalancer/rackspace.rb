require 'fog'

class Souffle::LoadBalancer::Rackspace < Souffle::LoadBalancer::Base
  
  # Setup the internal Rackspace configuration and object.
  def initialize
    super()
    begin
    @lbs = Fog::LoadBalancers::Rackspace.new({
      :rackspace_api_key  => @system.try_opt(:rackspace_access_key),
      :rackspace_username => @system.try_opt(:rackspace_access_name)
      })
    rescue => e
      Souffle::Log.error "#{e.class} :: #{e}"
    end
  end
  
  def create_lb(name, nodes, vips)
    vips = [ {"type" => "PUBLIC"}]
    nodes = [ {"address" => "10.176.98.127", "port" => 80, "condition" => "ENABLED"}]

    Souffle::Log.info "#{node.log_prefix} Adding Load Balanacer #{name}"
    @lbs.create_load_balancer("test_lb_from_fog", "HTTP", 80, vips, nodes)
  end
  
  def check_entry_status(job_id)
    @dns.callback(job_id).body["status"]
  end
end