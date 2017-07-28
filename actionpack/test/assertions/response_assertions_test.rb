require 'abstract_unit'
require 'action_dispatch/testing/assertions/response'

module ActionDispatch
  module Assertions
    class ResponseAssertionsTest < ActiveSupport::TestCase
      include ResponseAssertions

      FakeResponse = Struct.new(:response_code) do
        [:success, :missing, :redirect, :error].each do |sym|
          define_method("#{sym}?") do
            sym == response_code
          end
        end
      end

      def test_assert_response_predicate_methods
        [:success, :missing, :redirect, :error].each do |sym|
          @response = FakeResponse.new sym
          assert_response sym

          assert_raises(Minitest::Assertion) {
            assert_response :unauthorized
          }
        end
      end

      def test_assert_response_integer
        @response = FakeResponse.new 400
        assert_response 400

        assert_raises(Minitest::Assertion) {
          assert_response :unauthorized
        }

        assert_raises(Minitest::Assertion) {
          assert_response 500
        }
      end

      def test_assert_response_sym_status
        @response = FakeResponse.new 401
        assert_response :unauthorized

        assert_raises(Minitest::Assertion) {
          assert_response :ok
        }

        assert_raises(Minitest::Assertion) {
          assert_response :success
        }
      end

      def test_assert_response_sym_typo
        @response = FakeResponse.new 200

        assert_raises(ArgumentError) {
          assert_response :succezz
        }
      end
    end
  end
end
