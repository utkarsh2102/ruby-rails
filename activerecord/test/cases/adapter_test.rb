# encoding: utf-8

require "cases/helper"
require "models/book"
require "models/post"
require "models/author"

module ActiveRecord
  class AdapterTest < ActiveRecord::TestCase
    def setup
      @connection = ActiveRecord::Base.connection
    end

    ##
    # PostgreSQL does not support null bytes in strings
    unless current_adapter?(:PostgreSQLAdapter)
      def test_update_prepared_statement
        b = Book.create(name: "my \x00 book")
        b.reload
        assert_equal "my \x00 book", b.name
        b.update_attributes(name: "my other \x00 book")
        b.reload
        assert_equal "my other \x00 book", b.name
      end
    end

    def test_tables
      tables = @connection.tables
      assert tables.include?("accounts")
      assert tables.include?("authors")
      assert tables.include?("tasks")
      assert tables.include?("topics")
    end

    def test_table_exists?
      assert @connection.table_exists?("accounts")
      assert !@connection.table_exists?("nonexistingtable")
      assert !@connection.table_exists?(nil)
    end

    def test_indexes
      idx_name = "accounts_idx"

      if @connection.respond_to?(:indexes)
        indexes = @connection.indexes("accounts")
        assert indexes.empty?

        @connection.add_index :accounts, :firm_id, :name => idx_name
        indexes = @connection.indexes("accounts")
        assert_equal "accounts", indexes.first.table
        assert_equal idx_name, indexes.first.name
        assert !indexes.first.unique
        assert_equal ["firm_id"], indexes.first.columns
      else
        warn "#{@connection.class} does not respond to #indexes"
      end

    ensure
      @connection.remove_index(:accounts, :name => idx_name) rescue nil
    end

    def test_current_database
      if @connection.respond_to?(:current_database)
        assert_equal ARTest.connection_config['arunit']['database'], @connection.current_database
      end
    end

    if current_adapter?(:MysqlAdapter)
      def test_charset
        assert_not_nil @connection.charset
        assert_not_equal 'character_set_database', @connection.charset
        assert_equal @connection.show_variable('character_set_database'), @connection.charset
      end

      def test_collation
        assert_not_nil @connection.collation
        assert_not_equal 'collation_database', @connection.collation
        assert_equal @connection.show_variable('collation_database'), @connection.collation
      end

      def test_show_nonexistent_variable_returns_nil
        assert_nil @connection.show_variable('foo_bar_baz')
      end

      def test_not_specifying_database_name_for_cross_database_selects
        begin
          assert_nothing_raised do
            ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['arunit'].except(:database))

            config = ARTest.connection_config
            ActiveRecord::Base.connection.execute(
              "SELECT #{config['arunit']['database']}.pirates.*, #{config['arunit2']['database']}.courses.* " \
              "FROM #{config['arunit']['database']}.pirates, #{config['arunit2']['database']}.courses"
            )
          end
        ensure
          ActiveRecord::Base.establish_connection :arunit
        end
      end
    end

    def test_table_alias
      def @connection.test_table_alias_length() 10; end
      class << @connection
        alias_method :old_table_alias_length, :table_alias_length
        alias_method :table_alias_length,     :test_table_alias_length
      end

      assert_equal 'posts',      @connection.table_alias_for('posts')
      assert_equal 'posts_comm', @connection.table_alias_for('posts_comments')
      assert_equal 'dbo_posts',  @connection.table_alias_for('dbo.posts')

      class << @connection
        remove_method :table_alias_length
        alias_method :table_alias_length, :old_table_alias_length
      end
    end

    # test resetting sequences in odd tables in PostgreSQL
    if ActiveRecord::Base.connection.respond_to?(:reset_pk_sequence!)
      require 'models/movie'
      require 'models/subscriber'

      def test_reset_empty_table_with_custom_pk
        Movie.delete_all
        Movie.connection.reset_pk_sequence! 'movies'
        assert_equal 1, Movie.create(:name => 'fight club').id
      end

      def test_reset_table_with_non_integer_pk
        Subscriber.delete_all
        Subscriber.connection.reset_pk_sequence! 'subscribers'
        sub = Subscriber.new(:name => 'robert drake')
        sub.id = 'bob drake'
        assert_nothing_raised { sub.save! }
      end
    end

    def test_uniqueness_violations_are_translated_to_specific_exception
      @connection.execute "INSERT INTO subscribers(nick) VALUES('me')"
      assert_raises(ActiveRecord::RecordNotUnique) do
        @connection.execute "INSERT INTO subscribers(nick) VALUES('me')"
      end
    end

    unless current_adapter?(:SQLite3Adapter)
      def test_foreign_key_violations_are_translated_to_specific_exception
        assert_raises(ActiveRecord::InvalidForeignKey) do
          # Oracle adapter uses prefetched primary key values from sequence and passes them to connection adapter insert method
          if @connection.prefetch_primary_key?
            id_value = @connection.next_sequence_value(@connection.default_sequence_name("fk_test_has_fk", "id"))
            @connection.execute "INSERT INTO fk_test_has_fk (id, fk_id) VALUES (#{id_value},0)"
          else
            @connection.execute "INSERT INTO fk_test_has_fk (fk_id) VALUES (0)"
          end
        end
      end

      def test_foreign_key_violations_are_translated_to_specific_exception_with_validate_false
        klass_has_fk = Class.new(ActiveRecord::Base) do
          self.table_name = 'fk_test_has_fk'
        end

        assert_raises(ActiveRecord::InvalidForeignKey) do
          has_fk = klass_has_fk.new
          has_fk.fk_id = 1231231231
          has_fk.save(validate: false)
        end
      end
    end

    def test_disable_referential_integrity
      assert_nothing_raised do
        @connection.disable_referential_integrity do
          # Oracle adapter uses prefetched primary key values from sequence and passes them to connection adapter insert method
          if @connection.prefetch_primary_key?
            id_value = @connection.next_sequence_value(@connection.default_sequence_name("fk_test_has_fk", "id"))
            @connection.execute "INSERT INTO fk_test_has_fk (id, fk_id) VALUES (#{id_value},0)"
          else
            @connection.execute "INSERT INTO fk_test_has_fk (fk_id) VALUES (0)"
          end
          # should delete created record as otherwise disable_referential_integrity will try to enable constraints after executed block
          # and will fail (at least on Oracle)
          @connection.execute "DELETE FROM fk_test_has_fk"
        end
      end
    end

    def test_select_all_always_return_activerecord_result
      result = @connection.select_all "SELECT * FROM posts"
      assert result.is_a?(ActiveRecord::Result)
    end

    def test_select_methods_passing_a_association_relation
      author = Author.create!(name: 'john')
      Post.create!(author: author, title: 'foo', body: 'bar')
      query = author.posts.where(title: 'foo').select(:title)
      assert_equal({"title" => "foo"}, @connection.select_one(query.arel, nil, query.bind_values))
      assert_equal({"title" => "foo"}, @connection.select_one(query))
      assert @connection.select_all(query).is_a?(ActiveRecord::Result)
      assert_equal "foo", @connection.select_value(query)
      assert_equal ["foo"], @connection.select_values(query)
    end

    def test_select_methods_passing_a_relation
      Post.create!(title: 'foo', body: 'bar')
      query = Post.where(title: 'foo').select(:title)
      assert_equal({"title" => "foo"}, @connection.select_one(query.arel, nil, query.bind_values))
      assert_equal({"title" => "foo"}, @connection.select_one(query))
      assert @connection.select_all(query).is_a?(ActiveRecord::Result)
      assert_equal "foo", @connection.select_value(query)
      assert_equal ["foo"], @connection.select_values(query)
    end

    test "type_to_sql returns a String for unmapped types" do
      assert_equal "special_db_type", @connection.type_to_sql(:special_db_type)
    end

    unless current_adapter?(:PostgreSQLAdapter)
      def test_log_invalid_encoding
        assert_raise ActiveRecord::StatementInvalid do
          @connection.send :log, "SELECT 'ы' FROM DUAL" do
            raise 'ы'.force_encoding(Encoding::ASCII_8BIT)
          end
        end
      end
    end
  end

  class AdapterTestWithoutTransaction < ActiveRecord::TestCase
    self.use_transactional_fixtures = false

    class Klass < ActiveRecord::Base
    end

    def setup
      Klass.establish_connection :arunit
      @connection = Klass.connection
    end

    teardown do
      Klass.remove_connection
    end

    unless in_memory_db?
      test "transaction state is reset after a reconnect" do
        @connection.begin_transaction
        assert @connection.transaction_open?
        @connection.reconnect!
        assert !@connection.transaction_open?
      end

      test "transaction state is reset after a disconnect" do
        @connection.begin_transaction
        assert @connection.transaction_open?
        @connection.disconnect!
        assert !@connection.transaction_open?
      end
    end
  end
end
