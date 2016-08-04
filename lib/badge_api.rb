# frozen_string_literal: true
require_relative './number_formatter.rb'
require_relative './core_api'
require_relative './svg_template'
# class used to download badges from shields.io
#
# @!attribute original_params
#   @return [Hash] THe original params received from URL
# @!attribute output_buffer
#   @return [Stream] The Sinatra Stream to which the badge will be inserted into
# @!attribute downloads
#   @return [Hash] THe downloads count that will need to be displayed on the badge
class BadgeApi < CoreApi
  # constant that is used to show message for invalid badge
  INVALID_COUNT = 'invalid'

  BASE_URL = 'https://img.shields.io'

  attr_reader :output_buffer, :downloads, :original_params, :http_response, :params, :request

  # Initializes the instance with the params from controller, and will try to download the information about the rubygems
  # and then will try to download the badge to the output stream
  # @see #fetch_image_shield
  # @see RubygemsApi#fetch_downloads_data
  #
  # @param [Hash] params describe params
  # @option params [String] :color The color of the badge
  # @option params [String]:style The style of the badge
  # @option params [Boolean] :metric This will decide if the number will be formatted using metric or delimiters
  # @param [Sinatra::Stream] output_buffer describe output_buffer
  # @param [Number] downloads describe external_api_details
  # @return [void]
  def initialize(request, params, output_buffer, downloads, http_response)
    @params = params
    @request = request
    @original_params = CGI::parse(request.query_string)
    @output_buffer = output_buffer
    @downloads = downloads
    @http_response = http_response
    fetch_image_shield
  end

  # Fetches the param style from the params , and if is not present will return by default 'flat'
  #
  # @return [String] Returns the param style from params , otherwise will return by default 'flat'
  def style_param
    @style_param ||= @params.fetch('style', 'flat') || 'flat'
  end

  # Fetches the maxAge from the params , and if is not present will return by default 2592000
  #
  # @return [Integer] Returns the maxAge from params , otherwise will return by default 2592000
  def max_age_param
    @max_age_param ||= @params.fetch('maxAge', 2_592_000) || 2_592_000
  end

  # Fetches the link params from the original params used for social badges
  #
  # @return [String] Returns the link param otherwise empty string
  def link_param
    @link_param ||= @original_params.fetch('link', '') || ''
  end

  # Checks if the badge is a social badge and if the params contains links and returns the links for the badge
  #
  # @return [String] Returns the links used for social badges
  def style_additionals
    return if style_param != 'social' || link_param.blank?
    "&link=#{link_param[0]}&link=#{link_param[1]}"
  end

  # Fetches the logo from the params, otherwise empty string
  #
  # @return [String] Returns the logo from the params, otherwise empty string
  def logo_param
    @logo_param ||= @params.fetch('logo', '') || ''
  end

  # Fetches the logo width from the params, otherwise empty string
  #
  # @return [String] Returns the logo width from the params, otherwise empty string
  def logo_width
    @logo_width ||= @params.fetch('logoWidth', 0).to_s.to_i || 0
  end

  # Fetches the logo padding from the params, otherwise empty string
  #
  # @return [String] Returns the logo padding from the params, otherwise empty string
  def logo_padding
    @logo_padding ||= @params.fetch('logoPadding', 0).to_s.to_i || 0
  end

  # Checks if any additional params are present in URL and adds them to the URL constructed for the badge
  #
  # @return [String] Returns the URL query string used for displaying the badge
  def additional_params
    additionals = {
      'logo': logo_param,
      'logoWidth': logo_width,
      'logoPadding': logo_padding,
      'style': style_param,
      'maxAge': max_age_param.to_i
    }.delete_if { |_key, value| value.blank? || (value.is_a?(Numeric) && value.zero?) }
    additionals = additionals.to_query
    "#{additionals}#{style_additionals}"
  end

  # Method that is used to fetch the status of the badge
  #
  # @return [String] Returns the status of the badge
  def status_param
    @status_param ||= begin
      status_param = @params.fetch('label', 'downloads') || 'downloads'
      status_param = status_param.present? ? status_param : 'downloads'
      clean_image_label(status_param)
    end
  end

  # Method that is used to set the image extension
  #
  # @return [String] Returns the status of the badge
  def image_extension
    @image_extension ||= begin
      param_extension = @params['extension'].to_s
      available_extension?(param_extension) ? param_extension : 'svg'
    end
  end

  def image_colour
    @image_colour ||= @downloads.blank? ? 'lightgrey' : @params.fetch('color', 'blue')
  end

  # Method used to build the shield URL for fetching the SVG image
  # @see #format_number_of_downloads
  # @return [String] The URL that will be used in fetching the SVG image from shields.io server
  def build_badge_url(extension = image_extension)
    "#{BadgeApi::BASE_URL}/badge/#{status_param}-#{format_number_of_downloads}-#{image_colour}.#{extension}?#{additional_params}"
  end

  def svg_template
    @svg_template ||= SvgTemplate.new(self)
  end

  def customized_badge?
    @params['customized_badge'].present? ? CoreApi::CUSTOMIZED_BADGE : ''
  end

  # Method that is used for building the URL for fetching the SVG Image, and actually
  # making the HTTP connection and adding the response to the stream
  # @see #build_badge_url
  # @see Helper#fetch_data
  # @see Helper#print_to_output_buffer
  #
  # @return [void]
  def fetch_image_shield
    fetch_data(build_badge_url, 'request_name' => @params.fetch('request_name', nil), 'http_detect' => customized_badge?) do |http_response|
      print_to_output_buffer(http_response, @output_buffer)
    end
  end

  # callback that is called when http request fails
  def callback_error(error, options)
    super(error, options)
    output = svg_template.fetch_badge_image
    print_to_output_buffer(output, @output_buffer)
  end

  # Method that is used for formatting the number of downloads , if the number is blank, will return invalid,
  # otherwise will format the number using the configuration from params, either using metrics or delimiters
  # @see  NumberFormatter#initialize
  # @see NumberFormatter#formatted_display
  #
  # @return [String] If the downloads argument is blank will return invalid, otherwise will format the numbere either with metrics or delimiters
  def format_number_of_downloads
    @format_number_of_downloads ||= (@downloads.blank? ? BadgeApi::INVALID_COUNT : NumberFormatter.new(@downloads, @params).to_s)
  end
end
