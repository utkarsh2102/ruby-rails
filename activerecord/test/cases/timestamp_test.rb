require 'cases/helper'
require 'models/developer'
require 'models/owner'
require 'models/pet'
require 'models/toy'
require 'models/car'
require 'models/task'

class TimestampTest < ActiveRecord::TestCase
  fixtures :developers, :owners, :pets, :toys, :cars, :tasks

  def setup
    @developer = Developer.first
    @developer.update_columns(updated_at: Time.now.prev_month)
    @previously_updated_at = @developer.updated_at
  end

  def test_saving_a_changed_record_updates_its_timestamp
    @developer.name = "Jack Bauer"
    @developer.save!

    assert_not_equal @previously_updated_at, @developer.updated_at
  end

  def test_saving_a_unchanged_record_doesnt_update_its_timestamp
    @developer.save!

    assert_equal @previously_updated_at, @developer.updated_at
  end

  def test_touching_a_record_updates_its_timestamp
    previous_salary = @developer.salary
    @developer.salary = previous_salary + 10000
    @developer.touch

    assert_not_equal @previously_updated_at, @developer.updated_at
    assert_equal previous_salary + 10000, @developer.salary
    assert @developer.salary_changed?, 'developer salary should have changed'
    assert @developer.changed?, 'developer should be marked as changed'
    @developer.reload
    assert_equal previous_salary, @developer.salary
  end

  def test_touching_a_record_with_default_scope_that_excludes_it_updates_its_timestamp
    developer = @developer.becomes(DeveloperCalledJamis)

    developer.touch
    assert_not_equal @previously_updated_at, developer.updated_at
    developer.reload
    assert_not_equal @previously_updated_at, developer.updated_at
  end

  def test_saving_when_record_timestamps_is_false_doesnt_update_its_timestamp
    Developer.record_timestamps = false
    @developer.name = "John Smith"
    @developer.save!

    assert_equal @previously_updated_at, @developer.updated_at
  ensure
    Developer.record_timestamps = true
  end

  def test_saving_when_instance_record_timestamps_is_false_doesnt_update_its_timestamp
    @developer.record_timestamps = false
    assert Developer.record_timestamps

    @developer.name = "John Smith"
    @developer.save!

    assert_equal @previously_updated_at, @developer.updated_at
  end

  def test_touching_an_attribute_updates_timestamp
    previously_created_at = @developer.created_at
    @developer.touch(:created_at)

    assert !@developer.created_at_changed? , 'created_at should not be changed'
    assert !@developer.changed?, 'record should not be changed'
    assert_not_equal previously_created_at, @developer.created_at
    assert_not_equal @previously_updated_at, @developer.updated_at
  end

  def test_touching_an_attribute_updates_it
    task = Task.first
    previous_value = task.ending
    task.touch(:ending)
    assert_not_equal previous_value, task.ending
    assert_in_delta Time.now, task.ending, 1
  end

  def test_touching_a_record_without_timestamps_is_unexceptional
    assert_nothing_raised { Car.first.touch }
  end

  def test_saving_a_record_with_a_belongs_to_that_specifies_touching_the_parent_should_update_the_parent_updated_at
    pet   = Pet.first
    owner = pet.owner
    previously_owner_updated_at = owner.updated_at

    pet.name = "Fluffy the Third"
    pet.save

    assert_not_equal previously_owner_updated_at, pet.owner.updated_at
  end

  def test_destroying_a_record_with_a_belongs_to_that_specifies_touching_the_parent_should_update_the_parent_updated_at
    pet   = Pet.first
    owner = pet.owner
    previously_owner_updated_at = owner.updated_at

    pet.destroy

    assert_not_equal previously_owner_updated_at, pet.owner.updated_at
  end

  def test_saving_a_new_record_belonging_to_invalid_parent_with_touch_should_not_raise_exception
    klass = Class.new(Owner) do
      def self.name; 'Owner'; end
      validate { errors.add(:base, :invalid) }
    end

    pet = Pet.new(owner: klass.new)
    pet.save!

    assert pet.owner.new_record?
  end

  def test_saving_a_record_with_a_belongs_to_that_specifies_touching_a_specific_attribute_the_parent_should_update_that_attribute
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Pet'; end
      belongs_to :owner, :touch => :happy_at
    end

    pet   = klass.first
    owner = pet.owner
    previously_owner_happy_at = owner.happy_at

    pet.name = "Fluffy the Third"
    pet.save

    assert_not_equal previously_owner_happy_at, pet.owner.happy_at
  end

  def test_touching_a_record_with_a_belongs_to_that_uses_a_counter_cache_should_update_the_parent
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Pet'; end
      belongs_to :owner, :counter_cache => :use_count, :touch => true
    end

    pet = klass.first
    owner = pet.owner
    owner.update_columns(happy_at: 3.days.ago)
    previously_owner_updated_at = owner.updated_at

    pet.name = "I'm a parrot"
    pet.save

    assert_not_equal previously_owner_updated_at, pet.owner.updated_at
  end

  def test_touching_a_record_touches_parent_record_and_grandparent_record
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Toy'; end
      belongs_to :pet, :touch => true
    end

    toy = klass.first
    pet = toy.pet
    owner = pet.owner
    time = 3.days.ago

    owner.update_columns(updated_at: time)
    toy.touch
    owner.reload

    assert_not_equal time, owner.updated_at
  end

  def test_touching_a_record_touches_polymorphic_record
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Toy'; end
    end

    wheel_klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Wheel'; end
      belongs_to :wheelable, :polymorphic => true, :touch => true
    end

    toy = klass.first
    time = 3.days.ago
    toy.update_columns(updated_at: time)

    wheel = wheel_klass.new
    wheel.wheelable = toy
    wheel.save
    wheel.touch

    assert_not_equal time, toy.updated_at
  end

  def test_changing_parent_of_a_record_touches_both_new_and_old_parent_record
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Toy'; end
      belongs_to :pet, touch: true
    end

    toy1 = klass.find(1)
    old_pet = toy1.pet

    toy2 = klass.find(2)
    new_pet = toy2.pet
    time = 3.days.ago.at_beginning_of_hour

    old_pet.update_columns(updated_at: time)
    new_pet.update_columns(updated_at: time)

    toy1.pet = new_pet
    toy1.save!

    old_pet.reload
    new_pet.reload

    assert_not_equal time, new_pet.updated_at
    assert_not_equal time, old_pet.updated_at
  end

  def test_changing_parent_of_a_record_touches_both_new_and_old_polymorphic_parent_record
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Toy'; end
    end

    wheel_klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Wheel'; end
      belongs_to :wheelable, :polymorphic => true, :touch => true
    end

    toy1 = klass.find(1)
    toy2 = klass.find(2)

    wheel = wheel_klass.new
    wheel.wheelable = toy1
    wheel.save!

    time = 3.days.ago.at_beginning_of_hour

    toy1.update_columns(updated_at: time)
    toy2.update_columns(updated_at: time)

    wheel.wheelable = toy2
    wheel.save!

    toy1.reload
    toy2.reload

    assert_not_equal time, toy1.updated_at
    assert_not_equal time, toy2.updated_at
  end

  def test_clearing_association_touches_the_old_record
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Toy'; end
      belongs_to :pet, touch: true
    end

    toy = klass.find(1)
    pet = toy.pet
    time = 3.days.ago.at_beginning_of_hour

    pet.update_columns(updated_at: time)

    toy.pet = nil
    toy.save!

    pet.reload

    assert_not_equal time, pet.updated_at
  end

  def test_timestamp_attributes_for_create
    toy = Toy.first
    assert_equal toy.send(:timestamp_attributes_for_create), [:created_at, :created_on]
  end

  def test_timestamp_attributes_for_update
    toy = Toy.first
    assert_equal toy.send(:timestamp_attributes_for_update), [:updated_at, :updated_on]
  end

  def test_all_timestamp_attributes
    toy = Toy.first
    assert_equal toy.send(:all_timestamp_attributes), [:created_at, :created_on, :updated_at, :updated_on]
  end

  def test_timestamp_attributes_for_create_in_model
    toy = Toy.first
    assert_equal toy.send(:timestamp_attributes_for_create_in_model), [:created_at]
  end

  def test_timestamp_attributes_for_update_in_model
    toy = Toy.first
    assert_equal toy.send(:timestamp_attributes_for_update_in_model), [:updated_at]
  end

  def test_all_timestamp_attributes_in_model
    toy = Toy.first
    assert_equal toy.send(:all_timestamp_attributes_in_model), [:created_at, :updated_at]
  end
end
