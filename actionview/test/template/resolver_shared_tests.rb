# frozen_string_literal: true

module ResolverSharedTests
  attr_reader :tmpdir

  def run(*args)
    capture_exceptions do
      Dir.mktmpdir(nil, __dir__) { |dir| @tmpdir = dir; super }
    end
  end

  def with_file(filename, source = "File at #{filename}")
    path = File.join(tmpdir, filename)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def context
    @context ||= ActionView::LookupContext.new(resolver)
  end

  def test_can_find_with_no_extensions
    with_file "test/hello_world", "Hello default!"

    templates = resolver.find_all("hello_world", "test", false, locale: [:en], formats: [:html], variants: [:phone], handlers: [:erb])
    assert_equal 1, templates.size
    assert_equal "Hello default!",   templates[0].source
    assert_equal "test/hello_world", templates[0].virtual_path
    assert_nil templates[0].format
    assert_nil templates[0].variant
    assert_kind_of ActionView::Template::Handlers::Raw, templates[0].handler
  end

  def test_can_find_with_just_handler
    with_file "test/hello_world.erb", "Hello erb!"

    templates = resolver.find_all("hello_world", "test", false, locale: [:en], formats: [:html], variants: [:phone], handlers: [:erb])
    assert_equal 1, templates.size
    assert_equal "Hello erb!",   templates[0].source
    assert_equal "test/hello_world", templates[0].virtual_path
    assert_nil templates[0].format
    assert_nil templates[0].variant
    assert_kind_of ActionView::Template::Handlers::ERB, templates[0].handler
  end

  def test_can_find_with_format_and_handler
    with_file "test/hello_world.text.builder", "Hello plain text!"

    templates = resolver.find_all("hello_world", "test", false, locale: [:en], formats: [:html, :text], variants: [:phone], handlers: [:erb, :builder])
    assert_equal 1, templates.size
    assert_equal "Hello plain text!", templates[0].source
    assert_equal "test/hello_world",  templates[0].virtual_path
    assert_equal :text, templates[0].format
    assert_nil templates[0].variant
    assert_kind_of ActionView::Template::Handlers::Builder, templates[0].handler
  end

  def test_can_find_with_variant_format_and_handler
    with_file "test/hello_world.html+phone.erb", "Hello plain text!"

    templates = resolver.find_all("hello_world", "test", false, locale: [:en], formats: [:html], variants: [:phone], handlers: [:erb])
    assert_equal 1, templates.size
    assert_equal "Hello plain text!", templates[0].source
    assert_equal "test/hello_world",  templates[0].virtual_path
    assert_equal :html, templates[0].format
    assert_equal "phone", templates[0].variant
    assert_kind_of ActionView::Template::Handlers::ERB, templates[0].handler
  end

  def test_can_find_with_any_variant_format_and_handler
    with_file "test/hello_world.html+phone.erb", "Hello plain text!"

    templates = resolver.find_all("hello_world", "test", false, locale: [:en], formats: [:html], variants: :any, handlers: [:erb])
    assert_equal 1, templates.size
    assert_equal "Hello plain text!", templates[0].source
    assert_equal "test/hello_world",  templates[0].virtual_path
    assert_equal :html, templates[0].format
    assert_equal "phone", templates[0].variant
    assert_kind_of ActionView::Template::Handlers::ERB, templates[0].handler
  end

  def test_can_find_when_special_chars_in_path
    dir = "test +()[]{}"
    with_file "#{dir}/hello_world", "Hello funky path!"

    templates = resolver.find_all("hello_world", dir, false, locale: [:en], formats: [:html], variants: [:phone], handlers: [:erb])
    assert_equal 1, templates.size
    assert_equal "Hello funky path!", templates[0].source
    assert_equal "#{dir}/hello_world", templates[0].virtual_path
  end

  def test_doesnt_find_template_with_wrong_details
    with_file "test/hello_world.html.erb", "Hello plain text!"

    templates = resolver.find_all("hello_world", "test", false, locale: [], formats: [:xml], variants: :any, handlers: [:builder])
    assert_equal 0, templates.size

    templates = resolver.find_all("hello_world", "test", false, locale: [], formats: [:xml], variants: :any, handlers: [:erb])
    assert_equal 0, templates.size
  end

  def test_found_template_is_cached
    with_file "test/hello_world.html.erb", "Hello HTML!"

    a = context.find("hello_world", "test", false, [], {})
    b = context.find("hello_world", "test", false, [], {})
    assert_same a, b
  end

  def test_different_templates_when_cache_disabled
    with_file "test/hello_world.html.erb", "Hello HTML!"

    a = context.find("hello_world", "test", false, [], {})
    b = context.disable_cache { context.find("hello_world", "test", false, [], {}) }
    c = context.find("hello_world", "test", false, [], {})

    # disable_cache should give us a new object
    assert_not_same a, b

    # but it should not clear the cache
    assert_same a, c
  end

  def test_same_template_from_different_details_is_same_object
    with_file "test/hello_world.html.erb", "Hello HTML!"

    a = context.find("hello_world", "test", false, [], locale: [:en])
    b = context.find("hello_world", "test", false, [], locale: [:fr])
    assert_same a, b
  end

  def test_templates_with_optional_locale_shares_common_object
    with_file "test/hello_world.text.erb", "Generic plain text!"
    with_file "test/hello_world.fr.text.erb", "Texte en Francais!"

    en = context.find_all("hello_world", "test", false, [], locale: [:en])
    fr = context.find_all("hello_world", "test", false, [], locale: [:fr])

    assert_equal 1, en.size
    assert_equal 2, fr.size

    assert_equal "Generic plain text!", en[0].source
    assert_equal "Texte en Francais!",  fr[0].source
    assert_equal "Generic plain text!", fr[1].source

    assert_same en[0], fr[1]
  end

  def test_virtual_path_is_preserved_with_dot
    with_file "test/hello_world.html.erb", "Hello html!"

    template = context.find("hello_world.html", "test", false, [], {})
    assert_equal "test/hello_world.html", template.virtual_path

    template = context.find("hello_world", "test", false, [], {})
    assert_equal "test/hello_world", template.virtual_path
  end
end
