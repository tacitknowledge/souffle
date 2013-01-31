require 'fog'

class Souffle::LoadBalancer::Rackspace < Souffle::LoadBalancer::Base
  
  # Setup the internal Rackspace configuration and object.
  def initialize
    super()
    begin
    @lbs = Fog::Rackspace::LoadBalancers.new({
      :rackspace_api_key  => @system.try_opt(:rackspace_access_key),
      :rackspace_username => @system.try_opt(:rackspace_access_name),
      :rackspace_lb_endpoint => (@system.try_opt(:rackspace_lb_endpoint) || "https://ord.loadbalancers.api.rackspacecloud.com/v1.0/")
      })
    rescue => e
      Souffle::Log.error "#{e.class} :: #{e}"
    end
  end
  
  def create_lb(lb, nodes, vips)
    if @lbs.nil?
      initialize
    end
    lb_nodes = []
    nodes.each do |n|
      node = n.provisioner.provider.get_server(n)
      address = node.addresses["private"].first["addr"]
      Souffle::Log.info "#{n.log_prefix} #{lb[:name]} Address: #{address}"
      lb_nodes << {"address" => address, "port" => lb[:node_port], "condition" => "ENABLED" }
    end
    #vips = [ {"type" => "PUBLIC"}]
    #nodes = [ {"address" => "10.176.98.127", "port" => 80, "condition" => "ENABLED"}]

    Souffle::Log.info "#{lb[:system_tag]} Adding Load Balanacer Name: #{lb[:name]} Nodes: #{lb_nodes} Vips #{vips} "
    @lbs.create_load_balancer(lb[:name], "HTTP", lb[:lb_port], vips, lb_nodes)
  end

end