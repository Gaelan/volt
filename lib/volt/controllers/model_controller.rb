require 'volt/reactive/reactive_accessors'
require 'volt/utils/lifecycle_callbacks'
require 'volt/controllers/template_helpers'
require 'volt/controllers/collection_helpers'

module Volt
  class ModelController
    include ReactiveAccessors
    include LifecycleCallbacks
    include CollectionHelpers

    # A model controller will have its
    # class VoltTemplates
    #   include TemplateHelpers
    # end

    class_attribute :default_model
    reactive_accessor :current_model
    reactive_accessor :last_promise

    # The section is assigned a reference to a "DomSection" which has
    # the dom for the controllers view.
    attr_accessor :section

    # Setup before_action and after_action
    setup_action_helpers_in_class(:before_action, :after_action)

    # Container returns the node that is parent to all nodes in the section.
    def container
      section.container_node
    end

    def dom_nodes
      section.range
    end

    # Walks the dom_nodes range until it finds an element.  Typically this will
    # be the container element without the whitespace text nodes.
    def first_element
      range = dom_nodes
      nodes = `range.startContainer.childNodes`

      start_index = `range.startOffset`
      end_index = `range.endOffset`

      start_index.upto(end_index) do |index|
        node = `nodes[index]`

        # Return if an element
        return node if `node.nodeType === 1`
      end

      nil
    end

    # the u method provides an easy helper to render an unbonud binding.  This
    # means that the binding will not reactively update.  If no bindings are
    # bound on any model's from a query, the query will not be reactively
    # listened to.
    def u
      fail "the 'u' method requires a block" unless block_given?
      Volt::Computation.run_without_tracking { yield }
    end

    # yield_html renders the content passed into a tag as a string.  You can ```.watch!```
    # ```yield_html``` and it will be run again when anything in the template changes.
    def yield_html
      if (template_path = attrs.content_template_path)
        @yield_renderer ||= StringTemplateRenderer.new(@volt_app, self, template_path)
        @yield_renderer.html
      else
        # no template, empty string
        ''
      end
    end

    def self.model(val)
      self.default_model = val
    end

    # Sets the current model on this controller
    def model=(val)
      if val.is_a?(Promise)
        # Resolve the promise before setting
        self.last_promise = val

        val.then do |result|
          # Only assign if nothing else has been assigned since we started the resolve
          self.model = result if last_promise == val
        end.fail do |err|
          Volt.logger.error("Unable to resolve promise assigned to model on #{inspect}")
        end

        return
      end

      # Clear
      self.last_promise = nil

      # Start with a nil reactive value.
      self.current_model ||= Model.new

      if Symbol === val || String === val
        collections = [:page, :store, :params, :controller]
        if collections.include?(val.to_sym)
          self.current_model = send(val)
        else
          fail "#{val} is not the name of a valid model, choose from: #{collections.join(', ')}"
        end
      else
        self.current_model = val
      end
    end

    def model
      model = self.current_model

      # If the model is a proc, call it now
      model = model.call if model && model.is_a?(Proc)

      model
    end

    def self.new(volt_app, *args, &block)
      inst = allocate

      # In MRI initialize is private for some reason, so call it with send
      inst.send(:initialize, volt_app, *args, &block)

      if inst.instance_variable_get('@__init_called')
        inst.instance_variable_set('@__init_called', nil)
      else
        # Initialize was not called, we should warn since this is probably not
        # the intended behavior.
        Volt.logger.warn("super should be called when creating a custom initialize on class #{inst.class}")
      end

      inst
    end

    attr_accessor :attrs

    def initialize(volt_app, *args)
      @volt_app = volt_app
      @page = volt_app.page

      # Track that the initialize was called
      @__init_called = true

      default_model = self.class.default_model
      self.model = default_model if default_model

      if args[0]
        # Assign the first passed in argument to attrs
        self.attrs = args[0]

        # If a model attribute is passed in, we assign it directly
        self.model = attrs.locals[:model] if attrs.respond_to?(:model)
      end
    end

    def go(url)
      Volt.logger.warn('Deprecation warning: `go` has been renamed to `redirect_to` for consistency with other frameworks.')

      redirect_to(url)
    end

    # Change the url
    def redirect_to(url)
      # We might be in the rendering loop, so wait until the next tick before
      # we change the url
      Timers.next_tick do
        self.url.parse(url)
      end
    end

    def page
      @page.page
    end

    def flash
      @page.flash
    end

    def params
      @page.params
    end

    def local_store
      @page.local_store
    end

    def cookies
      @page.cookies
    end

    def url
      @page.url
    end

    def channel
      @page.channel
    end

    def tasks
      @page.tasks
    end

    def controller
      @controller ||= Model.new
    end

    # loaded? is a quick way to see if the model for the controller is loaded
    # yet.  If the model is there, it asks the model if its loaded.  If the model
    # was set to a promise, it waits for the promise to resolve.
    def loaded?
      if model.respond_to?(:loaded?)
        # There is a model and it is loaded
        return model.loaded?
      elsif last_promise || model.is_a?(Promise)
        # The model is a promise or is resolving
        return false
      else
        # Otherwise, its loaded
        return true
      end
    end

    def require_login(message = 'You must login to access this area.')
      unless Volt.current_user_id
        flash._notices << message
        redirect_to '/login'

        stop_chain
      end
    end

    # Raw marks a string as html safe, so bindings can be rendered as html.
    # With great power comes great responsibility.
    def raw(str)
      str = str.to_s unless str.is_a?(String)
      str.html_safe
    end

    # Check if this controller responds_to method, or the model
    def respond_to?(method_name)
      super || begin
        model = self.model

        model.respond_to?(method_name) if model
      end
    end

    def method_missing(method_name, *args, &block)
      model = self.model

      if model
        model.send(method_name, *args, &block)
      else
        super
      end
    end
  end
end
