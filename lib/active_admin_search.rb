# frozen_string_literal: true

require 'active_admin_search/version'
require 'active_admin'

# nodoc
module ActiveAdminSearch
  class Error < StandardError; end
  # get root
  def self.root
    File.dirname __dir__
  end

  # The main method that should be used in your registered page
  def active_admin_search!(opts = {})
    # we can't split this block into smaller chunks
    # so we just disable Metrics/BlockLength cop for it.
    collection_action :search do # rubocop:disable Metrics/BlockLength
    value_method = opts.fetch(:value_method, :id)
    display_method = opts.fetch(:display_method, :display_name)
    highlight = opts.fetch(:highlight, nil)
    default_scopes = Array.wrap(opts[:default_scope])
    skip_default_scopes = params.delete(:skip_default_scopes) || false
    includes = Array.wrap(opts[:includes])
    limit = opts.fetch(:limit, nil)
    # look at params first then to dsl method implementation
    additional_payload = params[:additional_payload] || Array.wrap(opts.fetch(:additional_payload, []))
    # by default active_admin_search! returns only 500 items.
    # to override default page size just pass default_per_page to options.
    # you can also change page size with params[:per_page] query parameter.
    # with params[:page]=2 you can retrieve next page.
    # you can return whole collection w/o pagination by providing `skip_pagination: true` option.
    skip_pagination = opts.fetch(:skip_pagination, false)
    default_per_page = opts.fetch(:default_per_page, 500)
    order_clause = opts.fetch(:order_clause, id: :desc)
    # ajaxChosen will send term key
    # which can be renamed with jsonTermKey option
    # so we can rename it in active_admin_search too.
    json_term_key = opts.fetch(:json_term_key, :term)
    # optional rename term key before putting in into ransack search
    term_key_rename = opts[:term_key_rename]

    # scope and pagination params
    search_scope = params[:scope]
    page_number = params[:page] || 1
    page_size = params[:per_page] || default_per_page

    # clean search params
    search_params = params.fetch(:q) { params.except(:controller, :action, json_term_key) }.dup
    search_params.delete_if do |_, v| # like ransack does
      [*v].all? do |i|
        i.blank? && i != false
      end
    end

    # if params has term key we will put it to search_params
    # with optional renaming of term key.
    if params[json_term_key]
      search_params[term_key_rename || json_term_key] = params[json_term_key]
    end

    # substitute 'id:' from value for particular key
    if json_term_key.present? && search_params[json_term_key].present? && search_params[json_term_key].match?(/^id:\d+/)
      search_params[:id_eq] = search_params.delete(json_term_key).sub(/^id:(\d+)/, '\1')
    end

    text_caller = ActiveAdminSearch.make_text_caller(highlight, search_params, self, display_method)

    # return empty collection if search_params is empty
    if search_params.blank?
      scope = resource_class.none
    else
      scope = end_of_association_chain
      unless skip_default_scopes
        default_scopes.each { |default_scope| scope = scope.public_send(default_scope) }
      end

      scope = scope.public_send(search_scope) if search_scope.present? && !search_scope.include?(',')
      search_scope.split(',').each { |s| scope = scope.public_send(s) } if search_scope.present? && search_scope.include?(',')
      scope = scope.includes(includes) if includes.any? # apply includes
      scope = scope.order(order_clause) if order_clause.present?
      if limit.present?
        scope = scope.limit(limit)
      elsif !skip_pagination
        scope = scope.page(page_number).per(page_size)
      end

      scope = apply_authorization_scope(scope)
      scope = scope.ransack(search_params).result
    end
    if decorator_class.present?
      scope = decorator_class.decorate_collection(scope)
    end

    result = scope.map do |record|
      row = {
          value: record.public_send(value_method),
          text: text_caller.call(record)
      }.merge(additional_payload.first.is_a?(Proc) ? additional_payload.first.call(record) : additional_payload.map { |key| [key, record.public_send(key)] }.to_h)
      row
    end

    render json: result
    end
  end

  def make_text_caller(highlight, search_params, context, display_method)
    # highlight value of particular key in response
    if highlight.present? && search_params[highlight].present?
       proc { |r| context.view_context.highlight(r.public_send(display_method), search_params[highlight]) }
    else
       proc { |r| r.public_send(display_method) }
    end
  end

  module_function :make_text_caller, :active_admin_search!
end

 ActiveAdmin::ResourceDSL.include ActiveAdminSearch
