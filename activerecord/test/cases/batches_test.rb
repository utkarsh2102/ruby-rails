require 'cases/helper'
require 'models/post'
require 'models/subscriber'

class EachTest < ActiveRecord::TestCase
  fixtures :posts, :subscribers

  def setup
    @posts = Post.order("id asc")
    @total = Post.count
    Post.count('id') # preheat arel's table cache
  end

  def test_each_should_execute_one_query_per_batch
    assert_queries(@total + 1) do
      Post.find_each(:batch_size => 1) do |post|
        assert_kind_of Post, post
      end
    end
  end

  def test_each_should_not_return_query_chain_and_execute_only_one_query
    assert_queries(1) do
      result = Post.find_each(:batch_size => 100000){ }
      assert_nil result
    end
  end

  def test_each_should_return_an_enumerator_if_no_block_is_present
    assert_queries(1) do
      Post.find_each(:batch_size => 100000).with_index do |post, index|
        assert_kind_of Post, post
        assert_kind_of Integer, index
      end
    end
  end

  if Enumerator.method_defined? :size
    def test_each_should_return_a_sized_enumerator
      assert_equal 11, Post.find_each(:batch_size => 1).size
      assert_equal 5, Post.find_each(:batch_size => 2, :start => 7).size
      assert_equal 11, Post.find_each(:batch_size => 10_000).size
    end
  end

  def test_each_enumerator_should_execute_one_query_per_batch
    assert_queries(@total + 1) do
      Post.find_each(:batch_size => 1).with_index do |post, index|
        assert_kind_of Post, post
        assert_kind_of Integer, index
      end
    end
  end

  def test_each_should_raise_if_select_is_set_without_id
    assert_raise(RuntimeError) do
      Post.select(:title).find_each(batch_size: 1) { |post|
        flunk "should not call this block"
      }
    end
  end

  def test_each_should_execute_if_id_is_in_select
    assert_queries(6) do
      Post.select("id, title, type").find_each(:batch_size => 2) do |post|
        assert_kind_of Post, post
      end
    end
  end

  def test_warn_if_limit_scope_is_set
    ActiveRecord::Base.logger.expects(:warn)
    Post.limit(1).find_each { |post| post }
  end

  def test_warn_if_order_scope_is_set
    ActiveRecord::Base.logger.expects(:warn)
    Post.order("title").find_each { |post| post }
  end

  def test_logger_not_required
    previous_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = nil
    assert_nothing_raised do
      Post.limit(1).find_each { |post| post }
    end
  ensure
    ActiveRecord::Base.logger = previous_logger
  end

  def test_find_in_batches_should_return_batches
    assert_queries(@total + 1) do
      Post.find_in_batches(:batch_size => 1) do |batch|
        assert_kind_of Array, batch
        assert_kind_of Post, batch.first
      end
    end
  end

  def test_find_in_batches_should_start_from_the_start_option
    assert_queries(@total) do
      Post.find_in_batches(:batch_size => 1, :start => 2) do |batch|
        assert_kind_of Array, batch
        assert_kind_of Post, batch.first
      end
    end
  end

  def test_find_in_batches_shouldnt_execute_query_unless_needed
    assert_queries(2) do
      Post.find_in_batches(:batch_size => @total) {|batch| assert_kind_of Array, batch }
    end

    assert_queries(1) do
      Post.find_in_batches(:batch_size => @total + 1) {|batch| assert_kind_of Array, batch }
    end
  end

  def test_find_in_batches_should_quote_batch_order
    c = Post.connection
    assert_sql(/ORDER BY #{c.quote_table_name('posts')}.#{c.quote_column_name('id')}/) do
      Post.find_in_batches(:batch_size => 1) do |batch|
        assert_kind_of Array, batch
        assert_kind_of Post, batch.first
      end
    end
  end

  def test_find_in_batches_should_not_use_records_after_yielding_them_in_case_original_array_is_modified
    not_a_post = "not a post"
    not_a_post.stubs(:id).raises(StandardError, "not_a_post had #id called on it")

    assert_nothing_raised do
      Post.find_in_batches(:batch_size => 1) do |batch|
        assert_kind_of Array, batch
        assert_kind_of Post, batch.first

        batch.map! { not_a_post }
      end
    end
  end

  def test_find_in_batches_should_ignore_the_order_default_scope
    # First post is with title scope
    first_post = PostWithDefaultScope.first
    posts = []
    PostWithDefaultScope.find_in_batches  do |batch|
      posts.concat(batch)
    end
    # posts.first will be ordered using id only. Title order scope should not apply here
    assert_not_equal first_post, posts.first
    assert_equal posts(:welcome), posts.first
  end

  def test_find_in_batches_should_not_ignore_the_default_scope_if_it_is_other_then_order
    special_posts_ids = SpecialPostWithDefaultScope.all.map(&:id).sort
    posts = []
    SpecialPostWithDefaultScope.find_in_batches do |batch|
      posts.concat(batch)
    end
    assert_equal special_posts_ids, posts.map(&:id)
  end

  def test_find_in_batches_should_not_modify_passed_options
    assert_nothing_raised do
      Post.find_in_batches({ batch_size: 42, start: 1 }.freeze){}
    end
  end

  def test_find_in_batches_should_use_any_column_as_primary_key
    nick_order_subscribers = Subscriber.order('nick asc')
    start_nick = nick_order_subscribers.second.nick

    subscribers = []
    Subscriber.find_in_batches(:batch_size => 1, :start => start_nick) do |batch|
      subscribers.concat(batch)
    end

    assert_equal nick_order_subscribers[1..-1].map(&:id), subscribers.map(&:id)
  end

  def test_find_in_batches_should_use_any_column_as_primary_key_when_start_is_not_specified
    assert_queries(Subscriber.count + 1) do
      Subscriber.find_each(:batch_size => 1) do |subscriber|
        assert_kind_of Subscriber, subscriber
      end
    end
  end

  def test_find_in_batches_should_return_an_enumerator
    enum = nil
    assert_queries(0) do
      enum = Post.find_in_batches(:batch_size => 1)
    end
    assert_queries(4) do
      enum.first(4) do |batch|
        assert_kind_of Array, batch
        assert_kind_of Post, batch.first
      end
    end
  end

  if Enumerator.method_defined? :size
    def test_find_in_batches_should_return_a_sized_enumerator
      assert_equal 11, Post.find_in_batches(:batch_size => 1).size
      assert_equal 6, Post.find_in_batches(:batch_size => 2).size
      assert_equal 4, Post.find_in_batches(:batch_size => 2, :start => 4).size
      assert_equal 4, Post.find_in_batches(:batch_size => 3).size
      assert_equal 1, Post.find_in_batches(:batch_size => 10_000).size
    end
  end
end
