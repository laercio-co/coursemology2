# frozen_string_literal: true
class Course::ControllerComponentHost
  include Componentize

  module Sidebar
    extend ActiveSupport::Concern

    # Get the sidebar items from this component.
    #
    # @return [Array] An array of hashes containing the sidebar items exposed by this component.
    #   See #{Course::ControllerComponentHost#sidebar} for the format.
    def sidebar_items
      []
    end
  end

  module Enableable
    extend ActiveSupport::Concern

    delegate :enabled_by_default?, to: :class
    delegate :key, to: :class

    module ClassMethods
      # @return [Boolean] the default enabled status of the component
      def enabled_by_default?
        true
      end

      # Unique key of the component, to serve as the key in settings and translations.
      #
      # @return [Symbol] the key
      def key
        name.underscore.tr('/', '_').to_sym
      end

      # Override this to customise the display name of the component.
      # The module name is the default display name.
      #
      # @return [String]
      def display_name
        name
      end

      # @return [Boolean] The gamfied status of the component. If true, the component will be
      #   disabled when the gamified flag in the course is false. Value is false by default.
      def gamified?
        false
      end

      # @return [Boolean] States whether a component can be disabled. Value is true by default.
      #   Used to hide
      def can_be_disabled?
        true
      end
    end
  end

  # Open the Componentize Base Component.
  const_get(:Component).module_eval do
    const_set(:ClassMethods, ::Module.new) unless const_defined?(:ClassMethods)

    include Sidebar
    include Enableable
  end

  # Eager load all the components declared.
  eager_load_components(File.join(__dir__, '../'))

  class << self
    # Returns all components which can be disabled.
    #
    # @return [Array<Class>] array of disable-able components
    def disableable_components
      @disableable_components ||= components.select(&:can_be_disabled?)
    end

    # Find the enabled components from settings.
    def find_enabled_components(all_components, settings)
      all_components.select do |m|
        # If the component cannot be disabled, ignore the settings
        enabled = m.can_be_disabled? ? settings.settings(m.key).enabled : true
        enabled.nil? ? m.enabled_by_default? : enabled
      end
    end
  end

  # Initializes the component host instance.
  #
  # This loads all components.
  #
  # @param [#settings] instance_settings Instance settings object.
  # @param [#settings] course_settings Course settings object.
  # @param context The context to execute all component instance methods on.
  def initialize(instance_settings, course_settings, context)
    @instance_settings = instance_settings
    @course_settings = course_settings
    @context = context

    components
  end

  # Instantiates the enabled components.
  #
  # @return [Array] The instantiated enabled components.
  def components
    @components ||= enabled_components.map { |component| component.new(@context) }
  end

  # Gets the component instance with the given key.
  #
  # @param [String|Symbol] component_key The key of the component to find.
  # @return [Object] The component with the given key.
  # @return [nil] If component is not enabled.
  def [](component_key)
    components.find { |component| component.key.to_s == component_key.to_s }
  end

  # Apply preferences to all the components, returns the enabled components.
  #
  # @return [Array<Class>] array of enabled components
  def enabled_components
    @enabled_components ||= begin
      Course::ControllerComponentHost.
        find_enabled_components(course_available_components, @course_settings)
    end
  end

  # Returns the enabled components in instance.
  #
  # @return [Array<Class>] array of enabled components in instance
  def instance_enabled_components
    @instance_enabled_components ||= begin
      all_components = Course::ControllerComponentHost.components
      Course::ControllerComponentHost.
        find_enabled_components(all_components, @instance_settings)
    end
  end

  # Returns the available components in Course, depending on the gamified flag in Course.
  #
  # @return [Array<Class>] array of enabled components in Course
  def course_available_components
    @course_available_components ||= begin
      if @context.current_course.gamified?
        instance_enabled_components
      else
        instance_enabled_components - instance_enabled_components.select(&:gamified?)
      end
    end
  end

  # Returns the components in Course which can be disabled.
  #
  # @return [Array<Class>] array of disable-able components in Course
  def course_disableable_components
    @course_disableable_components ||= course_available_components.select(&:can_be_disabled?)
  end

  # Gets the sidebar elements.
  #
  # Sidebar elements have the given format:
  #
  #   {
  #      key: :item_key, # The unique key of the item to identify it among others. Can be nil if
  #                      # there is no need to distinguish between items.
  #                      # +normal+ type elements must have a key because their ordering is a
  #                      # user setting.
  #      title: 'Sidebar Item Title',
  #      type: :admin, # Will be considered as +:normal+ if not set. Currently +:normal+, +:admin+,
  #                    # and +:settings+ are used.
  #      weight: 100, # The default weight of the item. Larger weights (heavier items) sink.
  #      path: path_to_the_component,
  #      unread: 0 # Number of unread items. Can be +nil+, if not needed.
  #   }
  #
  # The elements are rendered on all Course controller subclasses as part of a nested template.
  def sidebar_items
    @sidebar_items ||= components.map(&:sidebar_items).tap(&:flatten!)
  end
end
