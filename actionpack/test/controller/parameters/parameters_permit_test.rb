require 'abstract_unit'
require 'action_dispatch/http/upload'
require 'action_controller/metal/strong_parameters'

class ParametersPermitTest < ActiveSupport::TestCase
  def assert_filtered_out(params, key)
    assert !params.has_key?(key), "key #{key.inspect} has not been filtered out"
  end

  setup do
    @params = ActionController::Parameters.new(
      person: {
        age: '32',
        name: {
          first: 'David',
          last: 'Heinemeier Hansson'
        },
        addresses: [{city: 'Chicago', state: 'Illinois'}]
      }
    )

    @struct_fields = []
    %w(0 1 12).each do |number|
      ['', 'i', 'f'].each do |suffix|
        @struct_fields << "sf(#{number}#{suffix})"
      end
    end
  end

  test 'if nothing is permitted, the hash becomes empty' do
    params = ActionController::Parameters.new(id: '1234')
    permitted = params.permit
    assert permitted.permitted?
    assert permitted.empty?
  end

  test 'key: permitted scalar values' do
    values  = ['a', :a, nil]
    values += [0, 1.0, 2**128, BigDecimal.new(1)]
    values += [true, false]
    values += [Date.today, Time.now, DateTime.now]
    values += [STDOUT, StringIO.new, ActionDispatch::Http::UploadedFile.new(tempfile: __FILE__),
      Rack::Test::UploadedFile.new(__FILE__)]

    values.each do |value|
      params = ActionController::Parameters.new(id: value)
      permitted = params.permit(:id)
      assert_equal value, permitted[:id]

      @struct_fields.each do |sf|
        params = ActionController::Parameters.new(sf => value)
        permitted = params.permit(:sf)
        assert_equal value, permitted[sf]
      end
    end
  end

  test 'key: unknown keys are filtered out' do
    params = ActionController::Parameters.new(id: '1234', injected: 'injected')
    permitted = params.permit(:id)
    assert_equal '1234', permitted[:id]
    assert_filtered_out permitted, :injected
  end

  test 'key: arrays are filtered out' do
    [[], [1], ['1']].each do |array|
      params = ActionController::Parameters.new(id: array)
      permitted = params.permit(:id)
      assert_filtered_out permitted, :id

      @struct_fields.each do |sf|
        params = ActionController::Parameters.new(sf => array)
        permitted = params.permit(:sf)
        assert_filtered_out permitted, sf
      end
    end
  end

  test 'key: hashes are filtered out' do
    [{}, {foo: 1}, {foo: 'bar'}].each do |hash|
      params = ActionController::Parameters.new(id: hash)
      permitted = params.permit(:id)
      assert_filtered_out permitted, :id

      @struct_fields.each do |sf|
        params = ActionController::Parameters.new(sf => hash)
        permitted = params.permit(:sf)
        assert_filtered_out permitted, sf
      end
    end
  end

  test 'key: non-permitted scalar values are filtered out' do
    params = ActionController::Parameters.new(id: Object.new)
    permitted = params.permit(:id)
    assert_filtered_out permitted, :id

    @struct_fields.each do |sf|
      params = ActionController::Parameters.new(sf => Object.new)
      permitted = params.permit(:sf)
      assert_filtered_out permitted, sf
    end
  end

  test 'key: it is not assigned if not present in params' do
    params = ActionController::Parameters.new(name: 'Joe')
    permitted = params.permit(:id)
    assert !permitted.has_key?(:id)
  end

  test 'key to empty array: empty arrays pass' do
    params = ActionController::Parameters.new(id: [])
    permitted = params.permit(id: [])
    assert_equal [], permitted[:id]
  end

  test 'do not break params filtering on nil values' do
    params = ActionController::Parameters.new(a: 1, b: [1, 2, 3], c: nil)

    permitted = params.permit(:a, c: [], b: [])
    assert_equal 1, permitted[:a]
    assert_equal [1, 2, 3], permitted[:b]
    assert_equal nil, permitted[:c]
  end

  test 'key to empty array: arrays of permitted scalars pass' do
    [['foo'], [1], ['foo', 'bar'], [1, 2, 3]].each do |array|
      params = ActionController::Parameters.new(id: array)
      permitted = params.permit(id: [])
      assert_equal array, permitted[:id]
    end
  end

  test 'key to empty array: permitted scalar values do not pass' do
    ['foo', 1].each do |permitted_scalar|
      params = ActionController::Parameters.new(id: permitted_scalar)
      permitted = params.permit(id: [])
      assert_filtered_out permitted, :id
    end
  end

  test 'key to empty array: arrays of non-permitted scalar do not pass' do
    [[Object.new], [[]], [[1]], [{}], [{id: '1'}]].each do |non_permitted_scalar|
      params = ActionController::Parameters.new(id: non_permitted_scalar)
      permitted = params.permit(id: [])
      assert_filtered_out permitted, :id
    end
  end

  test "fetch raises ParameterMissing exception" do
    e = assert_raises(ActionController::ParameterMissing) do
      @params.fetch :foo
    end
    assert_equal :foo, e.param
  end

  test "fetch with a default value of a hash does not mutate the object" do
    params = ActionController::Parameters.new({})
    params.fetch :foo, {}
    assert_equal nil, params[:foo]
  end

  test 'hashes in array values get wrapped' do
    params = ActionController::Parameters.new(foo: [{}, {}])
    params[:foo].each do |hash|
      assert !hash.permitted?
    end
  end

  # Strong params has an optimization to avoid looping every time you read
  # a key whose value is an array and building a new object. We check that
  # optimization here.
  test 'arrays are converted at most once' do
    params = ActionController::Parameters.new(foo: [{}])
    assert_same params[:foo], params[:foo]
  end

  # Strong params has an internal cache to avoid duplicated loops in the most
  # common usage pattern. See the docs of the method `converted_arrays`.
  #
  # This test checks that if we push a hash to an array (in-place modification)
  # the cache does not get fooled, the hash is still wrapped as strong params,
  # and not permitted.
  test 'mutated arrays are detected' do
    params = ActionController::Parameters.new(users: [{id: 1}])

    permitted = params.permit(users: [:id])
    permitted[:users] << {injected: 1}
    assert_not permitted[:users].last.permitted?
  end

  test "fetch doesnt raise ParameterMissing exception if there is a default" do
    assert_equal "monkey", @params.fetch(:foo, "monkey")
    assert_equal "monkey", @params.fetch(:foo) { "monkey" }
  end

  test "not permitted is sticky beyond merges" do
    assert !@params.merge(a: "b").permitted?
  end

  test "permitted is sticky beyond merges" do
    @params.permit!
    assert @params.merge(a: "b").permitted?
  end

  test "modifying the parameters" do
    @params[:person][:hometown] = "Chicago"
    @params[:person][:family] = { brother: "Jonas" }

    assert_equal "Chicago", @params[:person][:hometown]
    assert_equal "Jonas", @params[:person][:family][:brother]
  end

  test "permit state is kept on a dup" do
    @params.permit!
    assert_equal @params.permitted?, @params.dup.permitted?
  end

  test "permit is recursive" do
    @params.permit!
    assert @params.permitted?
    assert @params[:person].permitted?
    assert @params[:person][:name].permitted?
    assert @params[:person][:addresses][0].permitted?
  end

  test "permitted takes a default value when Parameters.permit_all_parameters is set" do
    begin
      ActionController::Parameters.permit_all_parameters = true
      params = ActionController::Parameters.new({ person: {
        age: "32", name: { first: "David", last: "Heinemeier Hansson" }
      }})

      assert params.slice(:person).permitted?
      assert params[:person][:name].permitted?
    ensure
      ActionController::Parameters.permit_all_parameters = false
    end
  end

  test "permitting parameters as an array" do
    assert_equal "32", @params[:person].permit([ :age ])[:age]
  end

  test "to_h returns empty hash on unpermitted params" do
    assert @params.to_h.is_a? Hash
    assert_not @params.to_h.is_a? ActionController::Parameters
    assert @params.to_h.empty?
  end

  test "to_h returns converted hash on permitted params" do
    @params.permit!

    assert @params.to_h.is_a? Hash
    assert_not @params.to_h.is_a? ActionController::Parameters
    assert_equal @params.to_hash, @params.to_h
  end

  test "to_h returns converted hash when .permit_all_parameters is set" do
    begin
      ActionController::Parameters.permit_all_parameters = true
      params = ActionController::Parameters.new(crab: "Senjougahara Hitagi")

      assert params.to_h.is_a? Hash
      assert_not @params.to_h.is_a? ActionController::Parameters
      assert_equal({ "crab" => "Senjougahara Hitagi" }, params.to_h)
    ensure
      ActionController::Parameters.permit_all_parameters = false
    end
  end

  test "to_h returns always permitted parameter on unpermitted params" do
    params = ActionController::Parameters.new(
      controller: "users",
      action: "create",
      user: {
        name: "Sengoku Nadeko"
      }
    )

    assert_equal({ "controller" => "users", "action" => "create" }, params.to_h)
  end

  test "to_unsafe_h returns unfiltered params" do
    assert @params.to_h.is_a? Hash
    assert_not @params.to_h.is_a? ActionController::Parameters
    assert_equal @params.to_hash, @params.to_unsafe_h
  end
end
