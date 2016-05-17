# frozen_string_literal: true
require "spec_helper"

describe "bundle plugin" do
  describe "install a plugin" do
    it "downloads the plugin to user bundler dir" do
      build_git "foo" do |s|
        s.write "plugin.rb", ""
      end

      bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"

      expect(out).to include("Installed plugin foo")
    end

    it "installs a plugin from rubygems", :focused do
      build_gem "bundler-foo" do |s|
        s.write "plugin.rb"
      end

      bundle "plugin install rack --source \"file://#{gem_repo1}\""

      expect(out).to include("Installed plugin bundler-foo")
    end
  end

  describe "malformatted plugin" do
    it "doesn't install" do
      build_git "foo" do |s|
        s.write "plugin.rb", <<-RUBY
          class DemoPlugin < Bundler::Plugin::Base
            command "demop"

            raise "I am malformatted"
            def execute(command, args)
              puts "hello world"
            end
          end
        RUBY
      end

      bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"

      expect(out).not_to include("Installed plugin foo")
    end
  end

  describe "command line plugin" do
    it "executes" do
      build_git "foo" do |s|
        s.write "plugin.rb", <<-RUBY
          class DemoPlugin < Bundler::Plugin::Base
            command "demop"

            def execute(command, args)
              puts "hello world"
            end
          end
        RUBY
      end

      bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"

      bundle "demop"

      expect(out).to include("hello world")
    end

    it "executes with arguments" do
      build_git "foo" do |s|
        s.write "plugin.rb", <<-RUBY
          class DemoPlugin < Bundler::Plugin::Base
            command "demop"

            def execute(command, args)
              puts "Hello World! You gave me " + args.join(" ")
            end
          end
        RUBY
      end

      bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"

      bundle "demop chocolate margarita burger"

      expect(out).to include("Hello World! You gave me chocolate margarita burger")
    end
  end

  describe "source plugins" do
    context "pre-installed" do
      before do
        build_git "foo" do |s|
          s.write "plugin.rb", <<-RUBY
            class DemoPlugin < Bundler::Plugin::Base
              source :hg

              def source_get(source, name, version)
                return source + name
              end
            end
          RUBY
        end

        bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"
      end

      it "handles source blocks with type options" do
        build_lib "hg-test-gem", :path => lib_path("mercurial/hg-test-gem")

        install_gemfile <<-G
          source "#{lib_path("mercurial/")}", :type => :hg do
            gem "hg-test-gem"
          end
        G

        expect(out).to include("Using hg-test-gem")
      end
    end
  end

  describe "lifecycle hooks" do
    context "post-install hook" do
      before do
        build_repo2 do
          build_gem "yaml_spec"
        end

        build_git "foo" do |s|
          s.write "plugin.rb", <<-RUBY
            class DemoPlugin < Bundler::Plugin::Base
              add_hook("post-install") do |gem|
                puts "post-install hook is running"
              end
            end
          RUBY
        end

        bundle "plugin install foo --git file://#{lib_path("foo-1.0")}"
      end

      it "runs after a rubygem is installed" do
        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "yaml_spec"
        G
        expect(out).to include "post-install hook is running"
      end

      it "runs after a git gem is installed" do
        build_git "bar"
        install_gemfile <<-G
          gem "bar", :git => "file://#{lib_path("bar-1.0")}"
        G
        expect(out).to include "post-install hook is running"
      end

      it "runs with multiple registered hooks" do
        build_git "bar" do |s|
          s.write "plugin.rb", <<-RUBY
            class DemoPlugin2 < Bundler::Plugin::Base
              add_hook("post-install") do |gem|
                puts "another post-install hook is running"
              end
            end
          RUBY
        end

        bundle "plugin install bar --git file://#{lib_path("bar-1.0")}"

        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "yaml_spec"
        G

        expect(out).to include "post-install hook is running"
        expect(out).to include "another post-install hook is running"
      end
    end
  end
end
