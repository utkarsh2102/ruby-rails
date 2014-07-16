require "isolation/abstract_unit"

module ApplicationTests
  module RakeTests
    class RakeNotesTest < ActiveSupport::TestCase
      include ActiveSupport::Testing::Isolation

      def setup
        build_app
        require "rails/all"
        super
      end

      def teardown
        super
        teardown_app
      end

      test 'notes finds notes for certain file_types' do
        app_file "app/views/home/index.html.erb", "<% # TODO: note in erb %>"
        app_file "app/views/home/index.html.haml", "-# TODO: note in haml"
        app_file "app/views/home/index.html.slim", "/ TODO: note in slim"
        app_file "app/assets/javascripts/application.js.coffee", "# TODO: note in coffee"
        app_file "app/assets/javascripts/application.js", "// TODO: note in js"
        app_file "app/assets/stylesheets/application.css", "// TODO: note in css"
        app_file "app/assets/stylesheets/application.css.scss", "// TODO: note in scss"
        app_file "app/assets/stylesheets/application.css.sass", "// TODO: note in sass"
        app_file "app/assets/stylesheets/application.css.less", "// TODO: note in less"
        app_file "app/controllers/application_controller.rb", 1000.times.map { "" }.join("\n") << "# TODO: note in ruby"
        app_file "lib/tasks/task.rake", "# TODO: note in rake"
        app_file 'app/views/home/index.html.builder', '# TODO: note in builder'

        boot_rails
        require 'rake'
        require 'rdoc/task'
        require 'rake/testtask'

        Rails.application.load_tasks

        Dir.chdir(app_path) do
          output = `bundle exec rake notes`
          lines = output.scan(/\[([0-9\s]+)\](\s)/)

          assert_match(/note in erb/, output)
          assert_match(/note in haml/, output)
          assert_match(/note in slim/, output)
          assert_match(/note in ruby/, output)
          assert_match(/note in coffee/, output)
          assert_match(/note in js/, output)
          assert_match(/note in css/, output)
          assert_match(/note in scss/, output)
          assert_match(/note in sass/, output)
          assert_match(/note in less/, output)
          assert_match(/note in rake/, output)
          assert_match(/note in builder/, output)

          assert_equal 12, lines.size

          lines.each do |line|
            assert_equal 4, line[0].size
            assert_equal ' ', line[1]
          end
        end
      end

      test 'notes finds notes in default directories' do
        app_file "app/controllers/some_controller.rb", "# TODO: note in app directory"
        app_file "config/initializers/some_initializer.rb", "# TODO: note in config directory"
        app_file "db/some_seeds.rb", "# TODO: note in db directory"
        app_file "lib/some_file.rb", "# TODO: note in lib directory"
        app_file "test/some_test.rb", 1000.times.map { "" }.join("\n") << "# TODO: note in test directory"

        app_file "some_other_dir/blah.rb", "# TODO: note in some_other directory"

        boot_rails

        require 'rake'
        require 'rdoc/task'
        require 'rake/testtask'

        Rails.application.load_tasks

        Dir.chdir(app_path) do
          output = `bundle exec rake notes`
          lines = output.scan(/\[([0-9\s]+)\]/).flatten

          assert_match(/note in app directory/, output)
          assert_match(/note in config directory/, output)
          assert_match(/note in db directory/, output)
          assert_match(/note in lib directory/, output)
          assert_match(/note in test directory/, output)
          assert_no_match(/note in some_other directory/, output)

          assert_equal 5, lines.size

          lines.each do |line_number|
            assert_equal 4, line_number.size
          end
        end
      end

      test 'notes finds notes in custom directories' do
        app_file "app/controllers/some_controller.rb", "# TODO: note in app directory"
        app_file "config/initializers/some_initializer.rb", "# TODO: note in config directory"
        app_file "db/some_seeds.rb", "# TODO: note in db directory"
        app_file "lib/some_file.rb", "# TODO: note in lib directory"
        app_file "test/some_test.rb", 1000.times.map { "" }.join("\n") << "# TODO: note in test directory"

        app_file "some_other_dir/blah.rb", "# TODO: note in some_other directory"

        boot_rails

        require 'rake'
        require 'rdoc/task'
        require 'rake/testtask'

        Rails.application.load_tasks

        Dir.chdir(app_path) do
          output = `SOURCE_ANNOTATION_DIRECTORIES='some_other_dir' bundle exec rake notes`
          lines = output.scan(/\[([0-9\s]+)\]/).flatten

          assert_match(/note in app directory/, output)
          assert_match(/note in config directory/, output)
          assert_match(/note in db directory/, output)
          assert_match(/note in lib directory/, output)
          assert_match(/note in test directory/, output)

          assert_match(/note in some_other directory/, output)

          assert_equal 6, lines.size

          lines.each do |line_number|
            assert_equal 4, line_number.size
          end
        end
      end

      test 'custom rake task finds specific notes in specific directories' do
        app_file "app/controllers/some_controller.rb", "# TODO: note in app directory"
        app_file "lib/some_file.rb", "# OPTIMIZE: note in lib directory\n" << "# FIXME: note in lib directory"
        app_file "test/some_test.rb", 1000.times.map { "" }.join("\n") << "# TODO: note in test directory"

        app_file "lib/tasks/notes_custom.rake", <<-EOS
          require 'rails/source_annotation_extractor'
          task :notes_custom do
            tags = 'TODO|FIXME'
            opts = { dirs: %w(lib test), tag: true }
            SourceAnnotationExtractor.enumerate(tags, opts)
          end
        EOS

        boot_rails

        require 'rake'
        require 'rdoc/task'
        require 'rake/testtask'

        Rails.application.load_tasks

        Dir.chdir(app_path) do
          output = `bundle exec rake notes_custom`
          lines = output.scan(/\[([0-9\s]+)\]/).flatten

          assert_match(/\[FIXME\] note in lib directory/, output)
          assert_match(/\[TODO\] note in test directory/, output)
          assert_no_match(/OPTIMIZE/, output)
          assert_no_match(/note in app directory/, output)

          assert_equal 2, lines.size

          lines.each do |line_number|
            assert_equal 4, line_number.size
          end
        end
      end

      private
      def boot_rails
        super
        require "#{app_path}/config/environment"
      end
    end
  end
end
