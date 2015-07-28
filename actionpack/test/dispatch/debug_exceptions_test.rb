require 'abstract_unit'

class DebugExceptionsTest < ActionDispatch::IntegrationTest

  class Boomer
    attr_accessor :closed

    def initialize(detailed  = false)
      @detailed = detailed
      @closed = false
    end

    # We're obliged to implement this (even though it doesn't actually
    # get called here) to properly comply with the Rack SPEC
    def each
    end

    def close
      @closed = true
    end

    def method_that_raises
      raise StandardError.new 'error in framework'
    end

    def call(env)
      env['action_dispatch.show_detailed_exceptions'] = @detailed
      req = ActionDispatch::Request.new(env)
      case req.path
      when "/pass"
        [404, { "X-Cascade" => "pass" }, self]
      when "/not_found"
        raise AbstractController::ActionNotFound
      when "/runtime_error"
        raise RuntimeError
      when "/method_not_allowed"
        raise ActionController::MethodNotAllowed
      when "/unknown_http_method"
        raise ActionController::UnknownHttpMethod
      when "/not_implemented"
        raise ActionController::NotImplemented
      when "/unprocessable_entity"
        raise ActionController::InvalidAuthenticityToken
      when "/not_found_original_exception"
        raise ActionView::Template::Error.new('template', AbstractController::ActionNotFound.new)
      when "/missing_template"
        raise ActionView::MissingTemplate.new(%w(foo), 'foo/index', %w(foo), false, 'mailer')
      when "/bad_request"
        raise ActionController::BadRequest
      when "/missing_keys"
        raise ActionController::UrlGenerationError, "No route matches"
      when "/parameter_missing"
        raise ActionController::ParameterMissing, :missing_param_key
      when "/original_syntax_error"
        eval 'broke_syntax =' # `eval` need for raise native SyntaxError at runtime
      when "/syntax_error_into_view"
        begin
          eval 'broke_syntax ='
        rescue Exception => e
          template = ActionView::Template.new(File.read(__FILE__),
                                              __FILE__,
                                              ActionView::Template::Handlers::Raw.new,
                                              {})
          raise ActionView::Template::Error.new(template, e)
        end
      when "/framework_raises"
        method_that_raises
      else
        raise "puke!"
      end
    end
  end

  def setup
    app = ActiveSupport::OrderedOptions.new
    app.config = ActiveSupport::OrderedOptions.new
    app.config.assets = ActiveSupport::OrderedOptions.new
    app.config.assets.prefix = '/sprockets'
    Rails.stubs(:application).returns(app)
  end

  RoutesApp = Struct.new(:routes).new(SharedTestRoutes)
  ProductionApp  = ActionDispatch::DebugExceptions.new(Boomer.new(false), RoutesApp)
  DevelopmentApp = ActionDispatch::DebugExceptions.new(Boomer.new(true), RoutesApp)

  test 'skip diagnosis if not showing detailed exceptions' do
    @app = ProductionApp
    assert_raise RuntimeError do
      get "/", {}, {'action_dispatch.show_exceptions' => true}
    end
  end

  test 'skip diagnosis if not showing exceptions' do
    @app = DevelopmentApp
    assert_raise RuntimeError do
      get "/", {}, {'action_dispatch.show_exceptions' => false}
    end
  end

  test 'raise an exception on cascade pass' do
    @app = ProductionApp
    assert_raise ActionController::RoutingError do
      get "/pass", {}, {'action_dispatch.show_exceptions' => true}
    end
  end

  test 'closes the response body on cascade pass' do
    boomer = Boomer.new(false)
    @app = ActionDispatch::DebugExceptions.new(boomer)
    assert_raise ActionController::RoutingError do
      get "/pass", {}, {'action_dispatch.show_exceptions' => true}
    end
    assert boomer.closed, "Expected to close the response body"
  end

  test 'displays routes in a table when a RoutingError occurs' do
    @app = DevelopmentApp
    get "/pass", {}, {'action_dispatch.show_exceptions' => true}
    routing_table = body[/route_table.*<.table>/m]
    assert_match '/:controller(/:action)(.:format)', routing_table
    assert_match ':controller#:action', routing_table
    assert_no_match '&lt;|&gt;', routing_table, "there should not be escaped html in the output"
  end

  test 'displays request and response info when a RoutingError occurs' do
    @app = DevelopmentApp

    get "/pass", {}, {'action_dispatch.show_exceptions' => true}

    assert_select 'h2', /Request/
    assert_select 'h2', /Response/
  end

  test "rescue with diagnostics message" do
    @app = DevelopmentApp

    get "/", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 500
    assert_match(/puke/, body)

    get "/not_found", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 404
    assert_match(/#{AbstractController::ActionNotFound.name}/, body)

    get "/method_not_allowed", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 405
    assert_match(/ActionController::MethodNotAllowed/, body)

    get "/unknown_http_method", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 405
    assert_match(/ActionController::UnknownHttpMethod/, body)

    get "/bad_request", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 400
    assert_match(/ActionController::BadRequest/, body)

    get "/parameter_missing", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 400
    assert_match(/ActionController::ParameterMissing/, body)
  end

  test "rescue with text error for xhr request" do
    @app = DevelopmentApp
    xhr_request_env = {'action_dispatch.show_exceptions' => true, 'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'}

    get "/", {}, xhr_request_env
    assert_response 500
    assert_no_match(/<header>/, body)
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/RuntimeError\npuke/, body)

    get "/not_found", {}, xhr_request_env
    assert_response 404
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/#{AbstractController::ActionNotFound.name}/, body)

    get "/method_not_allowed", {}, xhr_request_env
    assert_response 405
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/ActionController::MethodNotAllowed/, body)

    get "/unknown_http_method", {}, xhr_request_env
    assert_response 405
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/ActionController::UnknownHttpMethod/, body)

    get "/bad_request", {}, xhr_request_env
    assert_response 400
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/ActionController::BadRequest/, body)

    get "/parameter_missing", {}, xhr_request_env
    assert_response 400
    assert_no_match(/<body>/, body)
    assert_equal "text/plain", response.content_type
    assert_match(/ActionController::ParameterMissing/, body)
  end

  test "does not show filtered parameters" do
    @app = DevelopmentApp

    get "/", {"foo"=>"bar"}, {'action_dispatch.show_exceptions' => true,
      'action_dispatch.parameter_filter' => [:foo]}
    assert_response 500
    assert_match("&quot;foo&quot;=&gt;&quot;[FILTERED]&quot;", body)
  end

  test "show registered original exception for wrapped exceptions" do
    @app = DevelopmentApp

    get "/not_found_original_exception", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 404
    assert_match(/AbstractController::ActionNotFound/, body)
  end

  test "named urls missing keys raise 500 level error" do
    @app = DevelopmentApp

    get "/missing_keys", {}, {'action_dispatch.show_exceptions' => true}
    assert_response 500

    assert_match(/ActionController::UrlGenerationError/, body)
  end

  test "show the controller name in the diagnostics template when controller name is present" do
    @app = DevelopmentApp
    get("/runtime_error", {}, {
      'action_dispatch.show_exceptions' => true,
      'action_dispatch.request.parameters' => {
        'action' => 'show',
        'id' => 'unknown',
        'controller' => 'featured_tile'
      }
    })
    assert_response 500
    assert_match(/RuntimeError\n\s+in FeaturedTileController/, body)
  end

  test "sets the HTTP charset parameter" do
    @app = DevelopmentApp

    get "/", {}, {'action_dispatch.show_exceptions' => true}
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
  end

  test 'uses logger from env' do
    @app = DevelopmentApp
    output = StringIO.new
    get "/", {}, {'action_dispatch.show_exceptions' => true, 'action_dispatch.logger' => Logger.new(output)}
    assert_match(/puke/, output.rewind && output.read)
  end

  test 'uses backtrace cleaner from env' do
    @app = DevelopmentApp
    cleaner = stub(:clean => ['passed backtrace cleaner'])
    get "/", {}, {'action_dispatch.show_exceptions' => true, 'action_dispatch.backtrace_cleaner' => cleaner}
    assert_match(/passed backtrace cleaner/, body)
  end

  test 'logs exception backtrace when all lines silenced' do
    output = StringIO.new
    backtrace_cleaner = ActiveSupport::BacktraceCleaner.new
    backtrace_cleaner.add_silencer { true }

    env = {'action_dispatch.show_exceptions' => true,
           'action_dispatch.logger' => Logger.new(output),
           'action_dispatch.backtrace_cleaner' => backtrace_cleaner}

    get "/", {}, env
    assert_operator((output.rewind && output.read).lines.count, :>, 10)
  end

  test 'display backtrace when error type is SyntaxError' do
    @app = DevelopmentApp

    get '/original_syntax_error', {}, {'action_dispatch.backtrace_cleaner' => ActiveSupport::BacktraceCleaner.new}

    assert_response 500
    assert_select '#Application-Trace' do
      assert_select 'pre code', /\(eval\):1: syntax error, unexpected/
    end
  end

  test 'display backtrace on template missing errors' do
    @app = DevelopmentApp

    get "/missing_template", nil, {}

    assert_select "header h1", /Template is missing/

    assert_select "#container h2", /^Missing template/

    assert_select '#Application-Trace'
    assert_select '#Framework-Trace'
    assert_select '#Full-Trace'

    assert_select 'h2', /Request/
  end

  test 'display backtrace when error type is SyntaxError wrapped by ActionView::Template::Error' do
    @app = DevelopmentApp

    get '/syntax_error_into_view', {}, {'action_dispatch.backtrace_cleaner' => ActiveSupport::BacktraceCleaner.new}

    assert_response 500
    assert_select '#Application-Trace' do
      assert_select 'pre code', /\(eval\):1: syntax error, unexpected/
    end
  end

  test 'debug exceptions app shows user code that caused the error in source view' do
    @app = DevelopmentApp
    Rails.stubs(:root).returns(Pathname.new('.'))
    cleaner = ActiveSupport::BacktraceCleaner.new.tap do |bc|
      bc.add_silencer { |line| line =~ /method_that_raises/ }
      bc.add_silencer { |line| line !~ %r{test/dispatch/debug_exceptions_test.rb} }
    end

    get '/framework_raises', {}, {'action_dispatch.backtrace_cleaner' => cleaner}

    # Assert correct error
    assert_response 500
    assert_select 'h2', /error in framework/

    # assert source view line is the call to method_that_raises
    assert_select 'div.source:not(.hidden)' do
      assert_select 'pre .line.active', /method_that_raises/
    end

    # assert first source view (hidden) that throws the error
    assert_select 'div.source:first' do
      assert_select 'pre .line.active', /raise StandardError\.new/
    end

    # assert application trace refers to line that calls method_that_raises is first
    assert_select '#Application-Trace' do
      assert_select 'pre code a:first', %r{test/dispatch/debug_exceptions_test\.rb:\d+:in `call}
    end

    # assert framework trace that that threw the error is first
    assert_select '#Framework-Trace' do
      assert_select 'pre code a:first', /method_that_raises/
    end
  end
end
