# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/system_testing/driver"
require "selenium/webdriver"

class DriverTest < ActiveSupport::TestCase
  test "initializing the driver" do
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium)
    assert_equal :selenium, driver.instance_variable_get(:@name)
  end

  test "initializing the driver with a browser" do
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, using: :chrome, screen_size: [1400, 1400], options: { url: "http://example.com/wd/hub" })
    assert_equal :selenium, driver.instance_variable_get(:@name)
    assert_equal :chrome, driver.instance_variable_get(:@browser).name
    assert_nil driver.instance_variable_get(:@browser).options
    assert_equal [1400, 1400], driver.instance_variable_get(:@screen_size)
    assert_equal ({ url: "http://example.com/wd/hub" }), driver.instance_variable_get(:@options)
  end

  test "initializing the driver with a headless chrome" do
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_chrome, screen_size: [1400, 1400], options: { url: "http://example.com/wd/hub" })
    assert_equal :selenium, driver.instance_variable_get(:@name)
    assert_equal :headless_chrome, driver.instance_variable_get(:@browser).name
    assert_instance_of Selenium::WebDriver::Chrome::Options, driver.instance_variable_get(:@browser).options
    assert_equal [1400, 1400], driver.instance_variable_get(:@screen_size)
    assert_equal ({ url: "http://example.com/wd/hub" }), driver.instance_variable_get(:@options)
  end

  test "initializing the driver with a headless firefox" do
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, using: :headless_firefox, screen_size: [1400, 1400], options: { url: "http://example.com/wd/hub" })
    assert_equal :selenium, driver.instance_variable_get(:@name)
    assert_equal :headless_firefox, driver.instance_variable_get(:@browser).name
    assert_instance_of Selenium::WebDriver::Firefox::Options, driver.instance_variable_get(:@browser).options
    assert_equal [1400, 1400], driver.instance_variable_get(:@screen_size)
    assert_equal ({ url: "http://example.com/wd/hub" }), driver.instance_variable_get(:@options)
  end

  test "initializing the driver with a poltergeist" do
    driver = ActionDispatch::SystemTesting::Driver.new(:poltergeist, screen_size: [1400, 1400], options: { js_errors: false })
    assert_equal :poltergeist, driver.instance_variable_get(:@name)
    assert_equal [1400, 1400], driver.instance_variable_get(:@screen_size)
    assert_equal ({ js_errors: false }), driver.instance_variable_get(:@options)
  end

  test "initializing the driver with a webkit" do
    driver = ActionDispatch::SystemTesting::Driver.new(:webkit, screen_size: [1400, 1400], options: { skip_image_loading: true })
    assert_equal :webkit, driver.instance_variable_get(:@name)
    assert_equal [1400, 1400], driver.instance_variable_get(:@screen_size)
    assert_equal ({ skip_image_loading: true }), driver.instance_variable_get(:@options)
  end

  test "registerable? returns false if driver is rack_test" do
    assert_not ActionDispatch::SystemTesting::Driver.new(:rack_test).send(:registerable?)
  end

  test "define extra capabilities using chrome" do
    driver_option = nil
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :chrome) do |option|
      option.add_argument("start-maximized")
      option.add_emulation(device_name: "iphone 6")
      option.add_preference(:detach, true)

      driver_option = option
    end
    driver.use

    expected = { "goog:chromeOptions" => { args: ["start-maximized"], mobileEmulation: { deviceName: "iphone 6" }, prefs: { detach: true } } }
    assert_equal expected, driver_option.as_json
  end

  test "define extra capabilities using headless_chrome" do
    driver_option = nil
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :headless_chrome) do |option|
      option.add_argument("start-maximized")
      option.add_emulation(device_name: "iphone 6")
      option.add_preference(:detach, true)

      driver_option = option
    end
    driver.use

    expected = { "goog:chromeOptions" => { args: ["start-maximized"], mobileEmulation: { deviceName: "iphone 6" }, prefs: { detach: true } } }
    assert_equal expected, driver_option.as_json
  end

  test "define extra capabilities using firefox" do
    driver_option = nil
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :firefox) do |option|
      option.add_preference("browser.startup.homepage", "http://www.seleniumhq.com/")
      option.add_argument("--host=127.0.0.1")

      driver_option = option
    end
    driver.use

    expected = { "moz:firefoxOptions" => { args: ["--host=127.0.0.1"], prefs: { "browser.startup.homepage" => "http://www.seleniumhq.com/" } } }
    assert_equal expected, driver_option.as_json
  end

  test "define extra capabilities using headless_firefox" do
    driver_option = nil
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :headless_firefox) do |option|
      option.add_preference("browser.startup.homepage", "http://www.seleniumhq.com/")
      option.add_argument("--host=127.0.0.1")

      driver_option = option
    end
    driver.use

    expected = { "moz:firefoxOptions" => { args: ["--host=127.0.0.1"], prefs: { "browser.startup.homepage" => "http://www.seleniumhq.com/" } } }
    assert_equal expected, driver_option.as_json
  end

  test "does not define extra capabilities" do
    driver = ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :firefox)

    assert_nothing_raised do
      driver.use
    end
  end

  test "preloads browser's driver_path" do
    called = false

    original_driver_path = ::Selenium::WebDriver::Chrome::Service.driver_path
    ::Selenium::WebDriver::Chrome::Service.driver_path = -> { called = true }

    ActionDispatch::SystemTesting::Driver.new(:selenium, screen_size: [1400, 1400], using: :chrome)

    assert called
  ensure
    ::Selenium::WebDriver::Chrome::Service.driver_path = original_driver_path
  end
end
