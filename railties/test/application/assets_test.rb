# -*- coding: utf-8 -*-
require 'isolation/abstract_unit'
require 'rack/test'
require 'active_support/json'

module ApplicationTests
  class AssetsTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation
    include Rack::Test::Methods

    def setup
      build_app(initializers: true)
      boot_rails
    end

    def teardown
      teardown_app
    end

    def precompile!(env = nil)
      quietly do
        precompile_task = "bundle exec rake assets:precompile #{env} --trace 2>&1"
        output = Dir.chdir(app_path) { %x[ #{precompile_task} ] }
        assert $?.success?, output
        output
      end
    end

    def clean_assets!
      quietly do
        assert Dir.chdir(app_path) { system('bundle exec rake assets:clobber') }
      end
    end

    def assert_file_exists(filename)
      assert Dir[filename].first, "missing #{filename}"
    end

    def assert_no_file_exists(filename)
      assert !File.exist?(filename), "#{filename} does exist"
    end

    test "assets routes have higher priority" do
      app_file "app/assets/images/rails.png", "notactuallyapng"
      app_file "app/assets/javascripts/demo.js.erb", "a = <%= image_path('rails.png').inspect %>;"

      app_file 'config/routes.rb', <<-RUBY
        Rails.application.routes.draw do
          get '*path', to: lambda { |env| [200, { "Content-Type" => "text/html" }, ["Not an asset"]] }
        end
      RUBY

      add_to_env_config "development", "config.assets.digest = false"

      require "#{app_path}/config/environment"

      get "/assets/demo.js"
      assert_equal 'a = "/assets/rails.png";', last_response.body.strip
    end

    test "assets do not require compressors until it is used" do
      app_file "app/assets/javascripts/demo.js.erb", "<%= :alert %>();"
      add_to_env_config "production", "config.assets.compile = true"

      ENV["RAILS_ENV"] = "production"
      require "#{app_path}/config/environment"

      assert !defined?(Uglifier)
      get "/assets/demo.js"
      assert_match "alert()", last_response.body
      assert defined?(Uglifier)
    end

    test "precompile creates the file, gives it the original asset's content and run in production as default" do
      app_file "app/assets/javascripts/application.js", "alert();"
      app_file "app/assets/javascripts/foo/application.js", "alert();"

      ENV["RAILS_ENV"] = nil
      precompile!

      files = Dir["#{app_path}/public/assets/application-*.js"]
      files << Dir["#{app_path}/public/assets/foo/application-*.js"].first
      files.each do |file|
        assert_not_nil file, "Expected application.js asset to be generated, but none found"
        assert_equal "alert();\n", File.read(file)
      end
    end

    def test_precompile_does_not_hit_the_database
      app_file "app/assets/javascripts/application.js", "alert();"
      app_file "app/assets/javascripts/foo/application.js", "alert();"
      app_file "app/controllers/users_controller.rb", <<-eoruby
        class UsersController < ApplicationController; end
      eoruby
      app_file "app/models/user.rb", <<-eoruby
        class User < ActiveRecord::Base; raise 'should not be reached'; end
      eoruby

      ENV['RAILS_ENV']  = 'production'
      ENV['DATABASE_URL'] = 'postgresql://baduser:badpass@127.0.0.1/dbname'

      precompile!

      files = Dir["#{app_path}/public/assets/application-*.js"]
      files << Dir["#{app_path}/public/assets/foo/application-*.js"].first
      files.each do |file|
        assert_not_nil file, "Expected application.js asset to be generated, but none found"
        assert_equal "alert();".strip, File.read(file).strip
      end
    ensure
      ENV.delete 'RAILS_ENV'
      ENV.delete 'DATABASE_URL'
    end

    test "precompile application.js and application.css and all other non JS/CSS files" do
      app_file "app/assets/javascripts/application.js", "alert();"
      app_file "app/assets/stylesheets/application.css", "body{}"

      app_file "app/assets/javascripts/someapplication.js", "alert();"
      app_file "app/assets/stylesheets/someapplication.css", "body{}"

      app_file "app/assets/javascripts/something.min.js", "alert();"
      app_file "app/assets/stylesheets/something.min.css", "body{}"

      app_file "app/assets/javascripts/something.else.js.erb", "alert();"
      app_file "app/assets/stylesheets/something.else.css.erb", "body{}"

      images_should_compile = ["a.png", "happyface.png", "happy_face.png", "happy.face.png",
                               "happy-face.png", "happy.happy_face.png", "happy_happy.face.png",
                               "happy.happy.face.png", "-happy.png", "-happy.face.png",
                               "_happy.face.png", "_happy.png"]

      images_should_compile.each do |filename|
        app_file "app/assets/images/#{filename}", "happy"
      end

      precompile!

      images_should_compile = ["a-*.png", "happyface-*.png", "happy_face-*.png", "happy.face-*.png",
                               "happy-face-*.png", "happy.happy_face-*.png", "happy_happy.face-*.png",
                               "happy.happy.face-*.png", "-happy-*.png", "-happy.face-*.png",
                               "_happy.face-*.png", "_happy-*.png"]

      images_should_compile.each do |filename|
        assert_file_exists("#{app_path}/public/assets/#{filename}")
      end

      assert_file_exists("#{app_path}/public/assets/application-*.js")
      assert_file_exists("#{app_path}/public/assets/application-*.css")

      assert_no_file_exists("#{app_path}/public/assets/someapplication-*.js")
      assert_no_file_exists("#{app_path}/public/assets/someapplication-*.css")

      assert_no_file_exists("#{app_path}/public/assets/something.min-*.js")
      assert_no_file_exists("#{app_path}/public/assets/something.min-*.css")

      assert_no_file_exists("#{app_path}/public/assets/something.else-*.js")
      assert_no_file_exists("#{app_path}/public/assets/something.else-*.css")
    end

    test "precompile something.js for directory containing index file" do
      add_to_config "config.assets.precompile = [ 'something.js' ]"
      app_file "app/assets/javascripts/something/index.js.erb", "alert();"

      precompile!

      assert_file_exists("#{app_path}/public/assets/something-*.js")
    end

    test 'precompile use assets defined in app env config' do
      add_to_env_config 'production', 'config.assets.precompile = [ "something.js" ]'

      app_file 'app/assets/javascripts/something.js.erb', 'alert();'

      precompile! 'RAILS_ENV=production'

      assert_file_exists("#{app_path}/public/assets/something-*.js")
    end

    test 'precompile use assets defined in app config and reassigned in app env config' do
      add_to_config 'config.assets.precompile = [ "something.js" ]'
      add_to_env_config 'production', 'config.assets.precompile += [ "another.js" ]'

      app_file 'app/assets/javascripts/something.js.erb', 'alert();'
      app_file 'app/assets/javascripts/another.js.erb', 'alert();'

      precompile! 'RAILS_ENV=production'

      assert_file_exists("#{app_path}/public/assets/something-*.js")
      assert_file_exists("#{app_path}/public/assets/another-*.js")
    end

    test "asset pipeline should use a Sprockets::Index when config.assets.digest is true" do
      add_to_config "config.action_controller.perform_caching = false"

      ENV["RAILS_ENV"] = "production"
      require "#{app_path}/config/environment"

      assert_equal Sprockets::Index, Rails.application.assets.class
    end

    test "precompile creates a manifest file with all the assets listed" do
      app_file "app/assets/images/rails.png", "notactuallyapng"
      app_file "app/assets/stylesheets/application.css.erb", "<%= asset_path('rails.png') %>"
      app_file "app/assets/javascripts/application.js", "alert();"

      precompile!
      manifest = Dir["#{app_path}/public/assets/.sprockets-manifest-*.json"].first

      assets = ActiveSupport::JSON.decode(File.read(manifest))
      assert_match(/application-([0-z]+)\.js/, assets["assets"]["application.js"])
      assert_match(/application-([0-z]+)\.css/, assets["assets"]["application.css"])
    end

    test "the manifest file should be saved by default in the same assets folder" do
      app_file "app/assets/javascripts/application.js", "alert();"
      add_to_config "config.assets.prefix = '/x'"

      precompile!

      manifest = Dir["#{app_path}/public/x/.sprockets-manifest-*.json"].first
      assets = ActiveSupport::JSON.decode(File.read(manifest))
      assert_match(/application-([0-z]+)\.js/, assets["assets"]["application.js"])
    end

    test "assets do not require any assets group gem when manifest file is present" do
      app_file "app/assets/javascripts/application.js", "alert();"
      add_to_env_config "production", "config.serve_static_files = true"

      ENV["RAILS_ENV"] = "production"
      precompile!

      manifest = Dir["#{app_path}/public/assets/.sprockets-manifest-*.json"].first
      assets = ActiveSupport::JSON.decode(File.read(manifest))
      asset_path = assets["assets"]["application.js"]

      require "#{app_path}/config/environment"

      # Checking if Uglifier is defined we can know if Sprockets was reached or not
      assert !defined?(Uglifier)
      get "/assets/#{asset_path}"
      assert_match "alert()", last_response.body
      assert !defined?(Uglifier)
    end

    test "precompile properly refers files referenced with asset_path and runs in the provided RAILS_ENV" do
      app_file "app/assets/images/rails.png", "notactuallyapng"
      app_file "app/assets/stylesheets/application.css.erb", "<%= asset_path('rails.png') %>"
      add_to_env_config "test", "config.assets.digest = true"

      precompile!('RAILS_ENV=test')

      file = Dir["#{app_path}/public/assets/application-*.css"].first
      assert_match(/\/assets\/rails-([0-z]+)\.png/, File.read(file))
    end

    test "precompile shouldn't use the digests present in manifest.json" do
      app_file "app/assets/images/rails.png", "notactuallyapng"

      app_file "app/assets/stylesheets/application.css.erb", "p { url: <%= asset_path('rails.png') %> }"

      ENV["RAILS_ENV"] = "production"
      precompile!

      manifest = Dir["#{app_path}/public/assets/.sprockets-manifest-*.json"].first
      assets = ActiveSupport::JSON.decode(File.read(manifest))
      asset_path = assets["assets"]["application.css"]

      app_file "app/assets/images/rails.png", "p { url: change }"

      precompile!
      assets = ActiveSupport::JSON.decode(File.read(manifest))

      assert_not_equal asset_path, assets["assets"]["application.css"]
    end

    test "precompile appends the md5 hash to files referenced with asset_path and run in production with digest true" do
      app_file "app/assets/images/rails.png", "notactuallyapng"
      app_file "app/assets/stylesheets/application.css.erb", "<%= asset_path('rails.png') %>"

      ENV["RAILS_ENV"] = "production"
      precompile!

      file = Dir["#{app_path}/public/assets/application-*.css"].first
      assert_match(/\/assets\/rails-([0-z]+)\.png/, File.read(file))
    end

    test "precompile should handle utf8 filenames" do
      filename = "レイルズ.png"
      app_file "app/assets/images/#{filename}", "not an image really"
      add_to_config "config.assets.precompile = [ /\.png$/, /application.(css|js)$/ ]"

      precompile!

      manifest = Dir["#{app_path}/public/assets/.sprockets-manifest-*.json"].first
      assets = ActiveSupport::JSON.decode(File.read(manifest))
      assert asset_path = assets["assets"].find { |(k, _)| k && k =~ /.png/ }[1]

      require "#{app_path}/config/environment"

      get "/assets/#{URI.parser.escape(asset_path)}"
      assert_match "not an image really", last_response.body
      assert_file_exists("#{app_path}/public/assets/#{asset_path}")
    end

    test "assets are cleaned up properly" do
      app_file "public/assets/application.js", "alert();"
      app_file "public/assets/application.css", "a { color: green; }"
      app_file "public/assets/subdir/broken.png", "not really an image file"

      clean_assets!

      files = Dir["#{app_path}/public/assets/**/*", "#{app_path}/tmp/cache/assets/development/*",
                  "#{app_path}/tmp/cache/assets/test/*", "#{app_path}/tmp/cache/assets/production/*"]
      assert_equal 0, files.length, "Expected no assets, but found #{files.join(', ')}"
    end

    test "assets routes are not drawn when compilation is disabled" do
      app_file "app/assets/javascripts/demo.js.erb", "<%= :alert %>();"
      add_to_config "config.assets.compile = false"

      ENV["RAILS_ENV"] = "production"
      require "#{app_path}/config/environment"

      get "/assets/demo.js"
      assert_equal 404, last_response.status
    end

    test "does not stream session cookies back" do
      app_file "app/assets/javascripts/demo.js.erb", "<%= :alert %>();"

      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          get '/omg', :to => "omg#index"
        end
      RUBY

      add_to_env_config "development", "config.assets.digest = false"

      require "#{app_path}/config/environment"

      class ::OmgController < ActionController::Base
        def index
          flash[:cool_story] = true
          render text: "ok"
        end
      end

      get "/omg"
      assert_equal 'ok', last_response.body

      get "/assets/demo.js"
      assert_match "alert()", last_response.body
      assert_equal nil, last_response.headers["Set-Cookie"]
    end

    test "files in any assets/ directories are not added to Sprockets" do
      %w[app lib vendor].each do |dir|
        app_file "#{dir}/assets/#{dir}_test.erb", "testing"
      end

      app_file "app/assets/javascripts/demo.js", "alert();"

      add_to_env_config "development", "config.assets.digest = false"

      require "#{app_path}/config/environment"

      get "/assets/demo.js"
      assert_match "alert();", last_response.body
      assert_equal 200, last_response.status
    end

    test "assets are concatenated when debug is off and compile is off either if debug_assets param is provided" do
      app_with_assets_in_view

      # config.assets.debug and config.assets.compile are false for production environment
      ENV["RAILS_ENV"] = "production"
      precompile!

      require "#{app_path}/config/environment"

      class ::PostsController < ActionController::Base ; end

      # the debug_assets params isn't used if compile is off
      get '/posts?debug_assets=true'
      assert_match(/<script src="\/assets\/application-([0-z]+)\.js"><\/script>/, last_response.body)
      assert_no_match(/<script src="\/assets\/xmlhr-([0-z]+)\.js"><\/script>/, last_response.body)
    end

    test "assets can access model information when precompiling" do
      app_file "app/models/post.rb", "class Post; end"
      app_file "app/assets/javascripts/application.js", "//= require_tree ."
      app_file "app/assets/javascripts/xmlhr.js.erb", "<%= Post.name %>"

      precompile!
      assert_equal "Post;\n", File.read(Dir["#{app_path}/public/assets/application-*.js"].first)
    end

    test "initialization on the assets group should set assets_dir" do
      require "#{app_path}/config/application"
      Rails.application.initialize!(:assets)
      assert_not_nil Rails.application.config.action_controller.assets_dir
    end

    test "enhancements to assets:precompile should only run once" do
      app_file "lib/tasks/enhance.rake", "Rake::Task['assets:precompile'].enhance { puts 'enhancement' }"
      output = precompile!
      assert_equal 1, output.scan("enhancement").size
    end

    test "digested assets are not mistakenly removed" do
      app_file "app/assets/application.js", "alert();"
      add_to_config "config.assets.compile = true"

      precompile!

      files = Dir["#{app_path}/public/assets/application-*.js"]
      assert_equal 1, files.length, "Expected digested application.js asset to be generated, but none found"
    end

    test "digested assets are removed from configured path" do
      app_file "public/production_assets/application.js", "alert();"
      add_to_env_config "production", "config.assets.prefix = 'production_assets'"

      ENV["RAILS_ENV"] = nil

      clean_assets!

      files = Dir["#{app_path}/public/production_assets/application-*.js"]
      assert_equal 0, files.length, "Expected application.js asset to be removed, but still exists"
    end

    test "asset urls should use the request's protocol by default" do
      app_with_assets_in_view
      add_to_config "config.asset_host = 'example.com'"
      add_to_env_config "development", "config.assets.digest = false"
      require "#{app_path}/config/environment"
      class ::PostsController < ActionController::Base; end

      get '/posts', {}, {'HTTPS'=>'off'}
      assert_match('src="http://example.com/assets/application.self.js', last_response.body)
      get '/posts', {}, {'HTTPS'=>'on'}
      assert_match('src="https://example.com/assets/application.self.js', last_response.body)
    end

    test "asset urls should be protocol-relative if no request is in scope" do
      app_file "app/assets/images/rails.png", "notreallyapng"
      app_file "app/assets/javascripts/image_loader.js.erb", "var src='<%= image_path('rails.png') %>';"
      add_to_config "config.assets.precompile = %w{rails.png image_loader.js}"
      add_to_config "config.asset_host = 'example.com'"
      add_to_env_config "development", "config.assets.digest = false"
      precompile!

      assert_match "src='//example.com/assets/rails.png'", File.read(Dir["#{app_path}/public/assets/image_loader-*.js"].first)
    end

    test "asset paths should use RAILS_RELATIVE_URL_ROOT by default" do
      ENV["RAILS_RELATIVE_URL_ROOT"] = "/sub/uri"
      app_file "app/assets/images/rails.png", "notreallyapng"
      app_file "app/assets/javascripts/app.js.erb", "var src='<%= image_path('rails.png') %>';"
      add_to_config "config.assets.precompile = %w{rails.png app.js}"
      add_to_env_config "development", "config.assets.digest = false"
      precompile!

      assert_match "src='/sub/uri/assets/rails.png'", File.read(Dir["#{app_path}/public/assets/app-*.js"].first)
    end

    test "assets:cache:clean should clean cache" do
      ENV["RAILS_ENV"] = "production"
      precompile!

      quietly do
        Dir.chdir(app_path){ `bundle exec rake assets:clobber` }
      end

      assert !File.exist?("#{app_path}/tmp/cache/assets")
    end

    private

    def app_with_assets_in_view
      app_file "app/assets/javascripts/application.js", "//= require_tree ."
      app_file "app/assets/javascripts/xmlhr.js", "function f1() { alert(); }"
      app_file "app/views/posts/index.html.erb", "<%= javascript_include_tag 'application' %>"

      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          get '/posts', :to => "posts#index"
        end
      RUBY
    end
  end
end
