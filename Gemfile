source "http://rubygems.org"
# Add dependencies required to use your gem here.
# Example:
#   gem "activesupport", ">= 2.3.5"

gem "yajl-ruby"
gem "eventmachine"
gem "amqp"
gem "state_machine"

gem "right_aws"

gem "mixlib-cli", ">= 1.1.0"
gem "mixlib-log", ">= 1.3.0"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "rspec", "~> 2.10.0"
  gem "yard", "~> 0.8"
  gem "redcarpet", "~> 2.1.1"
  gem "rdoc", "~> 3.12"
  gem "cucumber", ">= 0"
  gem "bundler", "~> 1.1.0"
  gem "jeweler", "~> 1.8.3"
  gem "ruby-graphviz", :require => "graphviz"
  gem (RUBY_VERSION =~ /^1\.9/ ? "simplecov" : "rcov"), ">= 0"
end
