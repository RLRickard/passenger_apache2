#
# Cookbook Name:: passenger_apache2
# Recipe:: source
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "build-essential"
include_recipe "chef-vault"

node.default['passenger']['apache_mpm']  = 'prefork'

case node['platform_family']
when "arch"
  package "apache"
when "rhel"
  package "httpd-devel"
  if node['platform_version'].to_f < 6.0
    package 'curl-devel'
  else
    package 'libcurl-devel'
    package 'openssl-devel'
    package 'zlib-devel'
  end
else
  apache_development_package =  if %w( worker threaded ).include? node['passenger']['apache_mpm']
                                  'apache2-threaded-dev'
                                else
                                  'apache2-prefork-dev'
                                end
  %W( #{apache_development_package} libapr1-dev libcurl4-gnutls-dev ).each do |pkg|
    package pkg do
      action :upgrade
    end
  end
end

if node['passenger']['enterprise']
  secrets_databag = chef_vault_item(node['passenger']['data_bag_name'], node['passenger']['data_bag_item'])
  gem_package "passenger" do
    action :remove
    options '-x'
  end
  gem_package "passenger-enterprise-server" do
    version node['passenger']['version']
    source "https://download:#{secrets_databag['enterprise_token']}@www.phusionpassenger.com/enterprise_gems/"
  end
  if secrets_databag.key?('enterprise_license')
    file "/etc/passenger-enterprise-license" do
      content secrets_databag['enterprise_license']
      mode "0644"
    end
  end
  node.override['passenger']['root_path'] = "#{node['languages']['ruby']['gems_dir']}/gems/passenger-enterprise-server-#{node['passenger']['version']}"
  node.override['passenger']['module_path'] = "#{node['passenger']['root_path']}/#{PassengerConfig.build_directory_for_version(node['passenger']['version'])}/apache2/mod_passenger.so"
else
  gem_package "passenger-enterprise-server" do
    action :remove
    options '-x'
  end
  gem_package "passenger" do
    version node['passenger']['version']
  end
end

execute "passenger_module" do
  command "#{node['passenger']['ruby_bin']} #{node['passenger']['root_path']}/bin/passenger-install-apache2-module _#{node['passenger']['version']}_ --auto"
  only_if { node['passenger']['install_module'] }
  # this is late eval'd when Chef converges this resource, and the
  # attribute may have been modified by the `mod_rails` recipe.
  not_if { ::File.exist?(node['passenger']['module_path']) }
end
