require 'fog'

class Souffle::LoadBalancer::Rackspace < Souffle::LoadBalancer::Base
  
  # Setup the internal Rackspace configuration and object.
  def initialize
    super()
    begin
    @lbs = Fog::Rackspace::LoadBalancers.new({
      :rackspace_api_key  => @system.try_opt(:rackspace_access_key),
      :rackspace_username => @system.try_opt(:rackspace_access_name),
      :rackspace_lb_endpoint => (@system.try_opt(:rackspace_lb_endpoint) || "https://ord.loadbalancers.api.rackspacecloud.com/v1.0")
      })
    rescue => e
      Souffle::Log.error "#{e.class} :: #{e}"
    end
  end
  
  def create_lb(lb, nodes, vips)
    initialize if @lbs.nil?
    lb_nodes = []
    nodes.each do |n|
      @node = n if @node.nil?
      node = n.provisioner.provider.get_server(n)
      address = node.addresses["private"].first["addr"]
      Souffle::Log.info "#{n.log_prefix} #{lb[:name]} Address: #{address}"
      lb_nodes << {"address" => address, "port" => lb[:node_port], "condition" => "ENABLED" }
    end
    #vips = [ {"type" => "PUBLIC"}]
    #nodes = [ {"address" => "10.176.98.127", "port" => 80, "condition" => "ENABLED"}]

    Souffle::Log.info "#{lb[:system_tag]} Adding Load Balancer Name: #{lb[:name]} Nodes: #{lb_nodes} Vips #{vips} "
    @lbs.create_load_balancer(lb[:name], "HTTP", lb[:lb_port], vips, lb_nodes)
    unless lb[:access_rules].nil?
      lb[:access_rules].each do |rule|
        Souffle::Log.info "#{lb[:system_tag]} Adding access rule for #{lb[:name]}. Address: #{rule[:address]} Action: #{rule[:action]}"
        create_access_rule(lb[:name], rule[:address], rule[:action])
      end
      #Souffle::Log.info "#{lb[:system_tag]} Adding access rules for #{lb[:name]}. Rules: #{lb[:access_rules]}"
      #create_access_rules(lb[:name], lb[:access_rules])
    end
    wait_for_lb(lb[:name])
    @lbs.set_monitor(get_lb_id(lb[:name]),"CONNECT",10,5,2)
    wait_for_lb(lb[:name])
    @lbs.update_load_balancer(get_lb_id(lb[:name]), :algorithm => "LEAST_CONNECTIONS")
  end
  
  def get_lb(name)
    initialize if @lbs.nil?
    lb = @lbs.load_balancers.select { |lb| lb.name == name }
  end
  
  def get_lb_ip(name)
    lb = get_lb(name)
    lb.first.virtual_ips.first.address
  end
  
  def get_lb_id(name)
    lb = get_lb(name)
    lb.first.id
  end
  
  def wait_for_lb(name)
    lb = get_lb(name)
    until(lb.first.state == "ACTIVE" || lb.first.state == "ERROR")
      if lb.first.state == "ERROR"
        Souffle::Log.error "[#{@node.log_prefix}] System Creation Failure."
        Souffle::Log.error "[#{@node.log_prefix}] Complete failure. Halting Creation."
        @node.system.provisioner.creation_halted
      end
      sleep 5
      lb = get_lb(name)
    end
  end
  
  def setup_lb_dns(dns_provider, name, domain, tag=nil)
    unless dns_provider.nil?
      @dns = Souffle::DNS.plugin(@system.try_opt(:dns_provider)).new
      @dns.create_entry_by_name(name, domain, get_lb_ip(name), tag)
    end
  end
  
  def set_ssl_termination(name, port, key, cert, opts={})
    initialize if @lbs.nil?
    wait_for_lb(name)
    @lbs.set_ssl_termination(get_lb_id(name), port, key, cert, opts)
  end
  
  def create_access_rule(name, address, action)
    initialize if @lbs.nil?
    wait_for_lb(name)
    @lbs.create_access_rule(get_lb_id(name), address, action)
  end
  
  def create_access_rules(name, rule_list)
    initialize if @lbs.nil?
    wait_for_lb(name)
    @lbs.create_access_rules(get_lb_id(name), rule_list)
  end
    
end
