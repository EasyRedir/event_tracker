require "event_tracker/version"
require "event_tracker/mixpanel"
require "event_tracker/intercom"
require "event_tracker/kissmetrics"
require "event_tracker/google_analytics"
require "event_tracker/facebook"
require "event_tracker/linked_in"

module EventTracker
  module HelperMethods
    def track_event(event_name, args = {})
      (session[:event_tracker_queue] ||= []) << [event_name, args]
    end

    def track_page_view_event(args = {})
      (session[:event_tracker_page_view_queue] ||= []) << ['Viewed Page', args]
    end

    def register_properties(args)
      (session[:registered_properties] ||= {}).merge!(args)
    end

    def mixpanel_set_config(args)
      (session[:mixpanel_set_config] ||= {}).merge!(args)
    end

    def mixpanel_people_set(args)
      (session[:mixpanel_people_set] ||= {}).merge!(args)
    end

    def mixpanel_people_set_once(args)
      (session[:mixpanel_people_set_once] ||= {}).merge!(args)
    end

    def mixpanel_people_increment(args)
      (session[:mixpanel_people_increment] ||= {}).merge!(args)
    end

    def mixpanel_alias(identity)
      session[:mixpanel_alias] = identity
    end
  end

  module ActionControllerExtension
    def mixpanel_tracker
      @mixpanel_tracker ||= begin
        mixpanel_key = Rails.application.config.event_tracker.mixpanel_key
        EventTracker::Mixpanel.new(mixpanel_key) if mixpanel_key
      end
    end

    def intercom_tracker
      @intercom_tracker ||= begin
        intercom_key = Rails.application.config.event_tracker.intercom_key
        EventTracker::Intercom.new(intercom_key) if intercom_key
      end
    end

    def kissmetrics_tracker
      @kissmetrics_tracker ||= begin
        kissmetrics_key = Rails.application.config.event_tracker.kissmetrics_key
        EventTracker::Kissmetrics.new(kissmetrics_key) if kissmetrics_key
      end
    end

    def facebook_tracker
      @facebook_tracker ||= begin
        facebook_key = Rails.application.config.event_tracker.facebook_key
        EventTracker::Facebook.new(facebook_key) if facebook_key
      end
    end

    def linked_in_tracker
      @linked_in_tracker ||= begin
        linked_in_key = Rails.application.config.event_tracker.linked_in_key
        EventTracker::LinkedIn.new(linked_in_key) if linked_in_key
      end
    end

    def google_analytics_tracker
      @google_analytics_tracker ||= begin
        google_analytics_key = Rails.application.config.event_tracker.google_analytics_key
        EventTracker::GoogleAnalytics.new(google_analytics_key) if google_analytics_key
      end
    end

    def event_trackers
      @event_trackers ||= begin
        trackers = []
        trackers << mixpanel_tracker if mixpanel_tracker
        trackers << intercom_tracker if intercom_tracker
        trackers << kissmetrics_tracker if kissmetrics_tracker
        trackers << google_analytics_tracker if google_analytics_tracker
        trackers << facebook_tracker if facebook_tracker
        trackers << linked_in_tracker if linked_in_tracker
        trackers
      end
    end

    def append_event_tracking_tags
      yield
      return if event_trackers.empty?

      body = response.body
      head_insert_at = body.index('</head')
      return unless head_insert_at

      body.insert head_insert_at, view_context.javascript_tag(event_trackers.map {|t| t.init }.join("\n"))
      body_insert_at = body.index('</body')
      return unless body_insert_at

      a = []
      if (mixpanel_alias = session.delete(:mixpanel_alias))
        a << mixpanel_tracker.alias(mixpanel_alias) if mixpanel_tracker
      elsif (distinct_id = respond_to?(:mixpanel_distinct_id, true) && mixpanel_distinct_id)
        a << mixpanel_tracker.identify(distinct_id) if mixpanel_tracker
      end

      if (name_tag = respond_to?(:mixpanel_name_tag, true) && mixpanel_name_tag)
        a << mixpanel_tracker.name_tag(name_tag) if mixpanel_tracker
      end

      if (config = session.delete(:mixpanel_set_config)).present?
        a << mixpanel_tracker.set_config(config) if mixpanel_tracker
      end

      if (people = session.delete(:mixpanel_people_set)).present?
        a << mixpanel_tracker.people_set(people) if mixpanel_tracker
      end

      if (people = session.delete(:mixpanel_people_set_once)).present?
        a << mixpanel_tracker.people_set_once(people) if mixpanel_tracker
      end

      if (people = session.delete(:mixpanel_people_increment)).present?
        a << mixpanel_tracker.people_increment(people) if mixpanel_tracker
      end

      if (settings = respond_to?(:intercom_settings, true) && intercom_settings)
        a << intercom_tracker.boot(settings) if intercom_tracker
      end

      if (identity = respond_to?(:google_analytics_identity, true) && google_analytics_identity)
        a << google_analytics_tracker.identify(identity) if google_analytics_tracker
      end

      if (identity = respond_to?(:kissmetrics_identity, true) && kissmetrics_identity)
        a << kissmetrics_tracker.identify(identity) if kissmetrics_tracker
      end

      registered_properties = session.delete(:registered_properties)
      event_tracker_queue = session.delete(:event_tracker_queue)
      event_tracker_page_view_queue = session.delete(:event_tracker_page_view_queue)

      a << google_analytics_tracker.track_pageview if google_analytics_tracker
      a << facebook_tracker.track_pageview if facebook_tracker

      event_trackers.each do |tracker|
        a << tracker.register(registered_properties) if registered_properties.present? && tracker.respond_to?(:register)

        if event_tracker_queue.present?
          event_tracker_queue.each do |event_name, properties|
            a << tracker.track(event_name, properties) if tracker.respond_to?(:track)
          end
        end

        if event_tracker_page_view_queue.present?
          event_tracker_page_view_queue.each do |event_name, properties|
            a << tracker.track(event_name, properties) if tracker.respond_to?(:track_page_views_as_events?) && tracker.track_page_views_as_events?
          end
        end
      end

      body.insert body_insert_at, view_context.javascript_tag(a.join("\n"))
      response.body = body
    end

  end

  class Railtie < Rails::Railtie
    config.event_tracker = ActiveSupport::OrderedOptions.new
    initializer "event_tracker" do |app|
      ActiveSupport.on_load :action_controller do
        include ActionControllerExtension
        include HelperMethods
        ::ActionController::Base.helper HelperMethods
      end
    end
  end
end
