require 'abstract_unit'
require 'rails/code_statistics'

class CodeStatisticsTest < ActiveSupport::TestCase
  def setup
    @tmp_path = File.expand_path(File.join(File.dirname(__FILE__), 'fixtures', 'tmp'))
    @dir_js   = File.expand_path(File.join(File.dirname(__FILE__), 'fixtures', 'tmp', 'lib.js'))
    FileUtils.mkdir_p(@dir_js)
  end

  def teardown
    FileUtils.rm_rf(@tmp_path)
  end

  test 'ignores directories that happen to have source files extensions' do
    assert_nothing_raised do
      @code_statistics = CodeStatistics.new(['tmp dir', @tmp_path])
    end
  end
end
