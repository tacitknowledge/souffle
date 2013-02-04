require 'fog'

class Souffle::DNS::Rackspace < Souffle::DNS::Base
  
  # Setup the internal Rackspace configuration and object.
  def initialize
    super()
    begin
    @dns = Fog::DNS::Rackspace.new({
      :rackspace_api_key  => @system.try_opt(:rackspace_access_key),
      :rackspace_username => @system.try_opt(:rackspace_access_name)
      })
    rescue => e
      Souffle::Log.error "#{e.class} :: #{e}"
    end
  end
  
  def create_entry(node, ip)
    create_entry_by_name(node.name, node.domain, ip)
  end
  
  def delete_entry(node)
    domain_id = @dns.list_domains.body["domains"].map {|d| d["id"] if d["name"] == "#{node.domain}"}.first
    begin
      record = @dns.list_records(domain_id).body["records"].map {|r| r["id"] if r["name"] == "#{node.name}.#{node.domain}"}.compact.first
    rescue Fog::DNS::Zerigo::NotFound
      record = nil
    end
    @dns.remove_record(record) if record
  end
  
  def check_entry_status(job_id)
    @dns.callback(job_id).body["status"]
  end
  
  def create_entry_by_name(name, domain, ip)
    domain_id = @dns.list_domains.body["domains"].map {|d| d["id"] if d["name"] == "#{domain}"}.first
    record = {}
    record[:name] = "#{name}.#{domain}"
    record[:type] = "A"
    record[:data] = "#{ip}"
    Souffle::Log.info "Adding DNS A Record #{record}"
    add_record = @dns.add_records(domain_id,[record])
    add_record.body["jobId"]
  end
end