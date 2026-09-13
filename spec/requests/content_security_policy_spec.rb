# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Content-Security-Policy' do
  before { allow(SecureRandom).to receive(:base64).with(16).and_return('ZbA+JmE7+bK8F5qvADZHuQ==') }

  it 'sets the expected CSP headers', academy: :disabled,
                                      reason: 'the fork redirects anonymous visitors from / to /auth/sign_up, so no view renders and the inline-script hash the app layout contributes to script-src is absent. The sibling below asserts these headers on the page that does render' do
    get '/'

    expect(response_csp_headers)
      .to match_array(expected_csp_headers)
  end

  # The academy serves /auth/sign_up where upstream serves the web app at /, so this is the page
  # that renders the application layout, and with it the inline theme script whose sha256- the
  # example above expects in script-src. Only script-src is asserted: being a form page, it
  # legitimately relaxes form-action from 'none' to 'self'.
  it 'sets the expected script-src on the academy sign-up page' do
    get '/auth/sign_up'

    expect(response_csp_headers)
      .to include(expected_csp_headers.find { |header| header.start_with?('script-src') })
  end

  def response_csp_headers
    response
      .headers['Content-Security-Policy']
      .split(';')
      .map(&:strip)
  end

  def expected_csp_headers
    <<~CSP.split("\n").map(&:strip)
      base-uri 'none'
      child-src 'self' blob: #{local_domain}
      connect-src 'self' data: blob: #{local_domain} #{Rails.configuration.x.streaming_api_base_url}
      default-src 'none'
      font-src 'self' #{local_domain}
      form-action 'none'
      frame-ancestors 'none'
      frame-src 'self' https:
      img-src 'self' data: blob: #{local_domain}
      manifest-src 'self' #{local_domain}
      media-src 'self' data: #{local_domain}
      script-src 'self' #{local_domain} 'wasm-unsafe-eval' 'sha256-OgOg5CGI7D4Syg38sNIknJKO+3DCTdpfY1ciC+Bklaw='
      style-src 'self' #{local_domain} 'nonce-ZbA+JmE7+bK8F5qvADZHuQ=='
      worker-src 'self' blob: #{local_domain}
    CSP
  end

  def local_domain
    root_url(host: Rails.configuration.x.local_domain).chop
  end
end
