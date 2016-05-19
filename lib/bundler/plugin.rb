# frozen_string_literal: true
module Bundler
  class Plugin
    autoload :Index, "bundler/plugin/index"
    autoload :Base, "bundler/plugin/base"

    @commands = {}             # The map of loaded commands
    @post_install_hooks = []   # Array of blocks
    @sources = {}              # The map of loaded sources

    class << self

      # Installs a plugin and registers it with the index
      def install(name, options)

        if options[:git]
          plugin_path = install_git name, options
        else
          plugin_path = install_rubygems name, options, plugin_path
        end

        plugin_path = Pathname.new plugin_path

        unless File.file? plugin_path.join("plugin.rb")
          raise "plugin.rb is not present in the gem"
        end

        register_plugin name, plugin_path

        Bundler.ui.info "Installed plugin #{name}"
      rescue StandardError => e
        Bundler.rm_rf(plugin_root.join(name))
        Bundler.ui.error "Failed to installed plugin #{name}: #{e.message}"
        Bundler.ui.error e.backtrace.join("\n  ")
      end

      def install_rubygems(name, options, plugin_path)
        version = options[:version] || [">= 0"]

        source = options.delete(:source) || raise("You need to provide the rubygems source")
        rg_source = Source::Rubygems.new("remotes" => source, :ignore_app_cache => true)
        rg_source.remote!
        rg_source.dependency_names << name

        dep = Dependency.new(name, version, options)

        deps = [DepProxy.new(dep, GemHelpers.generic_local_platform)]
        idx = rg_source.specs
        specs = Resolver.resolve(deps, idx).materialize([dep])

        raise "Plugin dependencies are not currently supported." if specs.size != 1
        install_from_spec specs.first
      end

      def install_from_spec(spec)
        raise "Gem spec doesn't have remote set" unless spec.remote
        uri = spec.remote.uri
        spec.fetch_platform

        download_path = plugin_cache.join(spec.name).to_s

        path = Bundler.rubygems.download_gem(spec, uri, download_path)

        Bundler.rubygems.preserve_paths do
          Bundler::RubyGemsGemInstaller.new(
            path,
            :install_dir         => plugin_root.to_s,
            :ignore_dependencies => true,
            :wrappers            => true,
            :env_shebang         => true
          ).install.full_gem_path
        end
      end

      def install_git(name, options)
        uri = options[:git]
        git_scope = "#{git_base_name uri}-#{git_uri_hash uri}"

        cache_path = plugin_cache.join("bundler", "git", git_scope)

        git_proxy = Source::Git::GitProxy.new(cache_path, uri, "master")
        git_proxy.checkout


        git_scope = "#{git_base_name uri}-#{git_shortref_for_path(git_proxy.revision)}"
        install_path = plugin_root.join("bundler", git_scope)

        git_proxy.copy_to(install_path)

        install_path
      end

      def git_base_name(uri)
        File.basename(uri.sub(%r{^(\w+://)?([^/:]+:)?(//\w*/)?(\w*/)*}, ""), ".git")
      end

      def git_shortref_for_path(ref)
        ref[0..11]
      end

      def git_uri_hash(uri)
        if uri =~ %r{^\w+://(\w+@)?}
          # Downcase the domain component of the URI
          # and strip off a trailing slash, if one is present
          input = URI.parse(uri).normalize.to_s.sub(%r{/$}, "")
        else
          # If there is no URI scheme, assume it is an ssh/git URI
          input = uri
        end
        Digest::SHA1.hexdigest(input)
      end

      # Saves the current state
      # Runs the plugin.rb
      # Passes the registerd commands to index
      # Restores the state
      def register_plugin(name, path)
        commands = @commands
        sources = @sources
        post_install_hooks = @post_install_hooks

        @commands = {}
        @post_install_hooks = []
        @sources = {}

        require path.join("plugin.rb")

        index.add_plugin name, path, @commands, @sources, @post_install_hooks
      ensure
        @commands = commands
        @post_install_hooks = post_install_hooks
        @sources = sources
      end

      # The ondemand loading of plugins
      def load_plugin(path)
        require Pathname.new(path).join("plugin.rb")
      end

      def index
        @index ||= Index.new(plugin_config_file)
      end

      # Directory where plugins will be stored
      def plugin_root
        Bundler.user_bundle_path.join("plugins")
      end

      # The config file for activated plugins
      def plugin_config_file
        Bundler.user_bundle_path.join("plugin")
      end

      # Cache to store the downloaded plugins
      def plugin_cache
        plugin_root.join("cache")
      end

      def add_command(command, command_class)
        @commands[command] = command_class
      end

      def command?(command)
        index.command? command
      end

      def exec(command, *args)
        raise "Unknown command" unless index.command? command

        load_plugin index.command_plugin(command) unless @commands.key? command

        cmd = @commands[command].new
        cmd.execute(command, args)
      end

      def register_post_install(&block)
        @post_install_hooks << block
      end

      def post_install(gem)
        if @post_install_hooks.length != index.post_install_hooks.length
          @post_install_hooks = []
          index.post_install_hooks.each {|p| load_plugin p }
        end

        @post_install_hooks.each do |cb|
          cb.call(gem)
        end
      end

      def add_source(name, cls)
        @sources[name] = cls
      end

      def source?(name)
        index.source? name
      end

      # Returns a block to be excuted with the gem name and version
      # and the plugin will fetch the gem to a local directory
      # and will return the path
      #
      # A workaround for demo. The real one will return a object of
      # class similar to Source::Git, maybe Source::Plugin with with the rest
      # of core infra can interact
      def source(source_name, source)
        raise "Unknown source" unless index.source? source_name

        load_plugin index.source_plugin(source_name) unless @sources.key? source_name

        obj = @sources[source_name].new

        proc do |name, version|
          # This downloads the gem from source and returns the path
          obj.source_get(source, name, version)
        end
      end
    end
  end
end
