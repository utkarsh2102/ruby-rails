# frozen_string_literal: true

require "cases/helper"

class DatabaseConfigurationsTest < ActiveRecord::TestCase
  unless in_memory_db?
    def test_empty_returns_true_when_db_configs_are_empty
      old_config = ActiveRecord::Base.configurations
      config = {}

      ActiveRecord::Base.configurations = config

      assert_predicate ActiveRecord::Base.configurations, :empty?
      assert_predicate ActiveRecord::Base.configurations, :blank?
    ensure
      ActiveRecord::Base.configurations = old_config
      ActiveRecord::Base.establish_connection :arunit
    end
  end

  def test_configs_for_getter_with_env_name
    configs = ActiveRecord::Base.configurations.configs_for(env_name: "arunit")

    assert_equal 1, configs.size
    assert_equal ["arunit"], configs.map(&:env_name)
  end

  def test_configs_for_getter_with_env_and_spec_name
    config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit", spec_name: "primary")

    assert_equal "arunit", config.env_name
    assert_equal "primary", config.spec_name
  end

  def test_default_hash_returns_config_hash_from_default_env
    original_rails_env = ENV["RAILS_ENV"]
    ENV["RAILS_ENV"] = "arunit"

    assert_equal ActiveRecord::Base.configurations.configs_for(env_name: "arunit", spec_name: "primary").config, ActiveRecord::Base.configurations.default_hash
  ensure
    ENV["RAILS_ENV"] = original_rails_env
  end

  def test_find_db_config_returns_a_db_config_object_for_the_given_env
    config = ActiveRecord::Base.configurations.find_db_config("arunit2")

    assert_equal "arunit2", config.env_name
    assert_equal "primary", config.spec_name
  end

  def test_to_h_turns_db_config_object_back_into_a_hash
    configs = ActiveRecord::Base.configurations
    assert_equal "ActiveRecord::DatabaseConfigurations", configs.class.name
    assert_equal "Hash", configs.to_h.class.name
    assert_equal ["arunit", "arunit2", "arunit_without_prepared_statements"], ActiveRecord::Base.configurations.to_h.keys.sort
  end
end

class LegacyDatabaseConfigurationsTest < ActiveRecord::TestCase
  unless in_memory_db?
    def test_setting_configurations_hash
      old_config = ActiveRecord::Base.configurations
      config = { "adapter" => "sqlite3" }

      assert_deprecated do
        ActiveRecord::Base.configurations["readonly"] = config
      end

      assert_equal ["arunit", "arunit2", "arunit_without_prepared_statements", "readonly"], ActiveRecord::Base.configurations.configs_for.map(&:env_name).sort
    ensure
      ActiveRecord::Base.configurations = old_config
      ActiveRecord::Base.establish_connection :arunit
    end
  end

  def test_can_turn_configurations_into_a_hash
    assert ActiveRecord::Base.configurations.to_h.is_a?(Hash), "expected to be a hash but was not."
    assert_equal ["arunit", "arunit2", "arunit_without_prepared_statements"].sort, ActiveRecord::Base.configurations.to_h.keys.sort
  end

  def test_each_is_deprecated
    assert_deprecated do
      all_configs = ActiveRecord::Base.configurations.values
      ActiveRecord::Base.configurations.each do |env_name, config|
        assert_includes ["arunit", "arunit2", "arunit_without_prepared_statements"], env_name
        assert_includes all_configs, config
      end
    end
  end

  def test_first_is_deprecated
    first_config = ActiveRecord::Base.configurations.configurations.map(&:config).first
    assert_deprecated do
      env_name, config = ActiveRecord::Base.configurations.first
      assert_equal "arunit", env_name
      assert_equal first_config, config
    end
  end

  def test_fetch_is_deprecated
    assert_deprecated do
      db_config = ActiveRecord::Base.configurations.fetch("arunit").first
      assert_equal "arunit", db_config.env_name
      assert_equal "primary", db_config.spec_name
    end
  end

  def test_values_are_deprecated
    config_hashes = ActiveRecord::Base.configurations.configurations.map(&:config)
    assert_deprecated do
      assert_equal config_hashes, ActiveRecord::Base.configurations.values
    end
  end

  def test_unsupported_method_raises
    assert_raises NotImplementedError do
      ActiveRecord::Base.configurations.select { |a| a == "foo" }
    end
  end
end
