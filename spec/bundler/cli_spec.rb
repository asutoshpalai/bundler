# frozen_string_literal: true

require "spec_helper"
require "bundler/cli"

describe "bundle executable" do
  it "returns non-zero exit status when passed unrecognized options" do
    bundle "--invalid_argument"
    expect(exitstatus).to_not be_zero if exitstatus
  end

  it "returns non-zero exit status when passed unrecognized task" do
    bundle "unrecognized-task"
    expect(exitstatus).to_not be_zero if exitstatus
  end

  it "accept the signals" do
    gemfile "gem 'rack'"
    system_gems "rack-1.0.0"

    create_file "hi", <<-RUBY
      #!/usr/bin/env ruby

      begin
        Thread.new do
          puts 'Started'                  # For process sync
          STDOUT.flush
          sleep 1
          raise "No Interrupt received"   # So that the test fails
        end.join
      rescue Interrupt
      end
      puts "foo"
    RUBY

    bundled_app.join("hi").chmod(0755)

    bundle("exec ./hi") do |i, o, thr|
      o.gets                      # Consumes 'Started' and ensures that thread has started
      Process.kill('INT', thr.pid)
    end

    expect(out).to eq('foo')
  end

  it "looks for a binary and executes it if it's named bundler-<task>" do
    File.open(tmp("bundler-testtasks"), "w", 0755) do |f|
      f.puts "#!/usr/bin/env ruby\nputs 'Hello, world'\n"
    end

    with_path_added(tmp) do
      bundle "testtasks"
    end

    expect(exitstatus).to be_zero if exitstatus
    expect(out).to eq("Hello, world")
  end

  context "when ENV['BUNDLE_GEMFILE'] is set to an empty string" do
    it "ignores it" do
      gemfile bundled_app("Gemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle :install, :env => { "BUNDLE_GEMFILE" => "" }

      should_be_installed "rack 1.0.0"
    end
  end

  context "when ENV['RUBYGEMS_GEMDEPS'] is set" do
    it "displays a warning" do
      gemfile bundled_app("Gemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle :install, :env => { "RUBYGEMS_GEMDEPS" => "foo" }
      expect(out).to include("RUBYGEMS_GEMDEPS")
      expect(out).to include("conflict with Bundler")

      bundle :install, :env => { "RUBYGEMS_GEMDEPS" => "" }
      expect(out).not_to include("RUBYGEMS_GEMDEPS")
    end
  end
end
