# encoding: utf-8
require "cases/helper"

class PostgresqlArrayTest < ActiveRecord::TestCase
  include InTimeZone
  OID = ActiveRecord::ConnectionAdapters::PostgreSQL::OID

  class PgArray < ActiveRecord::Base
    self.table_name = 'pg_arrays'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    enable_extension!('hstore', @connection)

    @connection.transaction do
      @connection.create_table('pg_arrays') do |t|
        t.string 'tags', array: true
        t.integer 'ratings', array: true
        t.datetime :datetimes, array: true
        t.hstore :hstores, array: true
      end
    end
    @column = PgArray.columns_hash['tags']
  end

  teardown do
    @connection.execute 'drop table if exists pg_arrays'
    disable_extension!('hstore', @connection)
  end

  def test_column
    assert_equal :string, @column.type
    assert_equal "character varying", @column.sql_type
    assert @column.array
    assert_not @column.number?
    assert_not @column.binary?

    ratings_column = PgArray.columns_hash['ratings']
    assert_equal :integer, ratings_column.type
    assert ratings_column.array
    assert_not ratings_column.number?
  end

  def test_default
    @connection.add_column 'pg_arrays', 'score', :integer, array: true, default: [4, 4, 2]
    PgArray.reset_column_information

    assert_equal([4, 4, 2], PgArray.column_defaults['score'])
    assert_equal([4, 4, 2], PgArray.new.score)
  ensure
    PgArray.reset_column_information
  end

  def test_default_strings
    @connection.add_column 'pg_arrays', 'names', :string, array: true, default: ["foo", "bar"]
    PgArray.reset_column_information

    assert_equal(["foo", "bar"], PgArray.column_defaults['names'])
    assert_equal(["foo", "bar"], PgArray.new.names)
  ensure
    PgArray.reset_column_information
  end

  def test_change_column_with_array
    @connection.add_column :pg_arrays, :snippets, :string, array: true, default: []
    @connection.change_column :pg_arrays, :snippets, :text, array: true, default: []

    PgArray.reset_column_information
    column = PgArray.columns_hash['snippets']

    assert_equal :text, column.type
    assert_equal [], PgArray.column_defaults['snippets']
    assert column.array
  end

  def test_change_column_cant_make_non_array_column_to_array
    @connection.add_column :pg_arrays, :a_string, :string
    assert_raises ActiveRecord::StatementInvalid do
      @connection.transaction do
        @connection.change_column :pg_arrays, :a_string, :string, array: true
      end
    end
  end

  def test_change_column_default_with_array
    @connection.change_column_default :pg_arrays, :tags, []

    PgArray.reset_column_information
    assert_equal [], PgArray.column_defaults['tags']
  end

  def test_type_cast_array
    assert_equal(['1', '2', '3'], @column.type_cast_from_database('{1,2,3}'))
    assert_equal([], @column.type_cast_from_database('{}'))
    assert_equal([nil], @column.type_cast_from_database('{NULL}'))
  end

  def test_type_cast_integers
    x = PgArray.new(ratings: ['1', '2'])

    assert_equal([1, 2], x.ratings)

    x.save!
    x.reload

    assert_equal([1, 2], x.ratings)
  end

  def test_select_with_strings
    @connection.execute "insert into pg_arrays (tags) VALUES ('{1,2,3}')"
    x = PgArray.first
    assert_equal(['1','2','3'], x.tags)
  end

  def test_rewrite_with_strings
    @connection.execute "insert into pg_arrays (tags) VALUES ('{1,2,3}')"
    x = PgArray.first
    x.tags = ['1','2','3','4']
    x.save!
    assert_equal ['1','2','3','4'], x.reload.tags
  end

  def test_select_with_integers
    @connection.execute "insert into pg_arrays (ratings) VALUES ('{1,2,3}')"
    x = PgArray.first
    assert_equal([1, 2, 3], x.ratings)
  end

  def test_rewrite_with_integers
    @connection.execute "insert into pg_arrays (ratings) VALUES ('{1,2,3}')"
    x = PgArray.first
    x.ratings = [2, '3', 4]
    x.save!
    assert_equal [2, 3, 4], x.reload.ratings
  end

  def test_multi_dimensional_with_strings
    assert_cycle(:tags, [[['1'], ['2']], [['2'], ['3']]])
  end

  def test_with_empty_strings
    assert_cycle(:tags, [ '1', '2', '', '4', '', '5' ])
  end

  def test_with_multi_dimensional_empty_strings
    assert_cycle(:tags, [[['1', '2'], ['', '4'], ['', '5']]])
  end

  def test_with_arbitrary_whitespace
    assert_cycle(:tags, [[['1', '2'], ['    ', '4'], ['    ', '5']]])
  end

  def test_multi_dimensional_with_integers
    assert_cycle(:ratings, [[[1], [7]], [[8], [10]]])
  end

  def test_strings_with_quotes
    assert_cycle(:tags, ['this has','some "s that need to be escaped"'])
  end

  def test_strings_with_commas
    assert_cycle(:tags, ['this,has','many,values'])
  end

  def test_strings_with_array_delimiters
    assert_cycle(:tags, ['{','}'])
  end

  def test_strings_with_null_strings
    assert_cycle(:tags, ['NULL','NULL'])
  end

  def test_contains_nils
    assert_cycle(:tags, ['1',nil,nil])
  end

  def test_insert_fixture
    tag_values = ["val1", "val2", "val3_with_'_multiple_quote_'_chars"]
    @connection.insert_fixture({"tags" => tag_values}, "pg_arrays" )
    assert_equal(PgArray.last.tags, tag_values)
  end

  def test_attribute_for_inspect_for_array_field
    record = PgArray.new { |a| a.ratings = (1..10).to_a }
    assert_equal("[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]", record.attribute_for_inspect(:ratings))
  end

  def test_attribute_for_inspect_for_array_field_for_large_array
    record = PgArray.new { |a| a.ratings = (1..11).to_a }
    assert_equal("[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]", record.attribute_for_inspect(:ratings))
  end

  def test_escaping
    unknown = 'foo\\",bar,baz,\\'
    tags = ["hello_#{unknown}"]
    ar = PgArray.create!(tags: tags)
    ar.reload
    assert_equal tags, ar.tags
  end

  def test_string_quoting_rules_match_pg_behavior
    tags = ["", "one{", "two}", %(three"), "four\\", "five ", "six\t", "seven\n", "eight,", "nine", "ten\r", "NULL"]
    x = PgArray.create!(tags: tags)
    x.reload

    assert_equal x.tags_before_type_cast, PgArray.columns_hash['tags'].type_cast_for_database(tags)
  end

  def test_string_datetime_array_match_pg_behavior
    date = Date.new(2017, 1, 2)
    oid = OID::Array.new(ActiveRecord::Type::Date.new)

    date_default = Date::DATE_FORMATS[:default]
    Date::DATE_FORMATS[:default] = '%d.%m.%Y'

    assert_equal "{'2017-01-02'}", oid.type_cast_for_database([date])

    Date::DATE_FORMATS[:default] = date_default
  end

  def test_quoting_non_standard_delimiters
    strings = ["hello,", "world;"]
    comma_delim = OID::Array.new(ActiveRecord::Type::String.new, ',')
    semicolon_delim = OID::Array.new(ActiveRecord::Type::String.new, ';')

    assert_equal %({"hello,",world;}), comma_delim.type_cast_for_database(strings)
    assert_equal %({hello,;"world;"}), semicolon_delim.type_cast_for_database(strings)
  end

  def test_mutate_array
    x = PgArray.create!(tags: %w(one two))

    x.tags << "three"
    x.save!
    x.reload

    assert_equal %w(one two three), x.tags
    assert_not x.changed?
  end

  def test_mutate_value_in_array
    x = PgArray.create!(hstores: [{ a: 'a' }, { b: 'b' }])

    x.hstores.first['a'] = 'c'
    x.save!
    x.reload

    assert_equal [{ 'a' => 'c' }, { 'b' => 'b' }], x.hstores
    assert_not x.changed?
  end

  def test_datetime_with_timezone_awareness
    tz = "Pacific Time (US & Canada)"

    in_time_zone tz do
      PgArray.reset_column_information
      time_string = Time.current.to_s
      time = Time.zone.parse(time_string)

      record = PgArray.new(datetimes: [time_string])
      assert_equal [time], record.datetimes
      assert_equal ActiveSupport::TimeZone[tz], record.datetimes.first.time_zone

      record.save!
      record.reload

      assert_equal [time], record.datetimes
      assert_equal ActiveSupport::TimeZone[tz], record.datetimes.first.time_zone
    end
  end

  def test_assigning_non_array_value
    record = PgArray.new(tags: "not-an-array")
    assert_equal [], record.tags
    assert_equal "not-an-array", record.tags_before_type_cast
    assert record.save
    assert_equal record.tags, record.reload.tags
  end

  def test_assigning_empty_string
    record = PgArray.new(tags: "")
    assert_equal [], record.tags
    assert_equal "", record.tags_before_type_cast
    assert record.save
    assert_equal record.tags, record.reload.tags
  end

  def test_assigning_valid_pg_array_literal
    record = PgArray.new(tags: "{1,2,3}")
    assert_equal ["1", "2", "3"], record.tags
    assert_equal "{1,2,3}", record.tags_before_type_cast
    assert record.save
    assert_equal record.tags, record.reload.tags
  end

  private
  def assert_cycle field, array
    # test creation
    x = PgArray.create!(field => array)
    x.reload
    assert_equal(array, x.public_send(field))

    # test updating
    x = PgArray.create!(field => [])
    x.public_send("#{field}=", array)
    x.save!
    x.reload
    assert_equal(array, x.public_send(field))
  end
end
