# frozen_string_literal: true
require "bundler/vendored_thor"
module Bundler
  class CLI::Plugin < Thor
    desc "install PLUGIN ", "Install the plugin"
    method_option "git", :type => :string, :default => nil, :banner =>
      "The git repo to install the plugin from"
    method_option "source", :type => :string, :default => nil, :banner =>
      "The RubyGems source to install the plugin from"
    def install(plugin)
      Bundler::Plugin.install(plugin, options)
    end
  end
end
