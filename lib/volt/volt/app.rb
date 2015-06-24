require 'opal'

# on the client, we want to include the main volt.rb file
require 'volt'
require 'volt/models'
require 'volt/controllers/model_controller'
require 'volt/tasks/task'
require 'volt/page/bindings/bindings'
require 'volt/page/template_renderer'
require 'volt/page/string_template_renderer'
require 'volt/page/document_events'
require 'volt/page/sub_context'
require 'volt/page/targets/dom_target'
require 'volt/data_stores/base_adaptor_client'

if RUBY_PLATFORM == 'opal'
  require 'volt/page/channel'
else
  require 'volt/page/channel_stub'
end
require 'volt/router/routes'
require 'volt/models/url'
require 'volt/page/url_tracker'
require 'volt/benchmark/benchmark'
require 'volt/page/tasks'
require 'volt/page/page'

require 'volt/volt/server_setup/app' unless RUBY_PLATFORM == 'opal'

module Volt
  class App
    if RUBY_PLATFORM != 'opal'
      # Include server app setup
      include Volt::ServerSetup::App
    end

    attr_reader :component_paths, :router, :page, :live_query_pool,
                :channel_live_queries, :app_path, :database, :message_bus,
                :middleware
    attr_accessor :sprockets

    def initialize(app_path = nil)
      if Volt.server? && !app_path
        fail 'Volt::App.new requires an app path to boot'
      end

      @app_path = app_path
      $volt_app = self

      # Setup root path
      Volt.root = app_path

      setup_page

      if RUBY_PLATFORM != 'opal'
        # We need to run the root config first so we can setup the Rack::Session
        # middleware.
        run_config

        # Setup all of the middleware we can before we load the users components
        # since the users components might want to add middleware during boot.
        setup_preboot_middleware

        # Setup all app paths
        setup_paths

        # Require in app and initializers
        run_app_and_initializers unless RUBY_PLATFORM == 'opal'

        # abort_on_exception is a useful debugging tool, and in my opinion something
        # you probbaly want on.  That said you can disable it if you need.
        unless RUBY_PLATFORM == 'opal'
          Thread.abort_on_exception = Volt.config.abort_on_exception
        end

        load_app_code

        reset_query_pool!

        # Setup the middleware that we can only setup after all components boot.
        setup_postboot_middleware

        start_message_bus
      end
    end

    # Setup a Page instance.
    def setup_page
      # Run the app config to load all users config files
      @page = Page.new(self)

      # Setup a global for now
      $page = @page unless defined?($page)
    end
  end
end

if Volt.client?
  $volt_app = Volt::App.new

  `$(document).ready(function() {`
  $volt_app.page.start
  `});`
end
