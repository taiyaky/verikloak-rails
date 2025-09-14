# frozen_string_literal: true

require 'spec_helper'


# Stub base error if the base gem is not loaded
module ::Verikloak; end unless defined?(::Verikloak)
unless defined?(::Verikloak::Error)
  class ::Verikloak::Error < StandardError
    attr_reader :code
    def initialize(code = 'unauthorized', message = nil)
      @code = code
      super(message || code)
    end
  end
end

RSpec.describe Verikloak::Rails::ErrorRenderer do
  let(:renderer) { described_class.new }

  let(:controller) do
    Class.new do
      attr_reader :response, :rendered
      def initialize
        @response = Class.new {
          attr_reader :headers
          def initialize
            @headers = {}
          end
          def set_header(k, v)
            @headers[k] = v
          end
        }.new
      end
      def render(json:, status:)
        @rendered = { json: json, status: status }
      end
    end.new
  end

  it 'renders 401 with WWW-Authenticate for invalid_token' do
    error = ::Verikloak::Error.new('invalid_token', 'Bad')
    renderer.render(controller, error)

    expect(controller.rendered[:status]).to eq(401)
    expect(controller.rendered[:json]).to eq(error: 'invalid_token', message: 'Bad')
    expect(controller.response.headers['WWW-Authenticate']).to include('error="invalid_token"')
    expect(controller.response.headers['WWW-Authenticate']).to include('error_description="Bad"')
  end

  it 'renders 403 for forbidden' do
    error = ::Verikloak::Error.new('forbidden', 'no')
    renderer.render(controller, error)
    expect(controller.rendered[:status]).to eq(403)
    expect(controller.rendered[:json]).to eq(error: 'forbidden', message: 'no')
  end

  it 'renders 401 for non-Verikloak errors' do
    error = StandardError.new('oops')
    renderer.render(controller, error)
    expect(controller.rendered[:status]).to eq(401)
    expect(controller.rendered[:json][:error]).to eq('standard') # derived from class name
  end

  it 'maps jwks_fetch_failed to 503 without WWW-Authenticate' do
    error = ::Verikloak::Error.new('jwks_fetch_failed', 'jwks down')
    renderer.render(controller, error)
    expect(controller.rendered[:status]).to eq(503)
    expect(controller.response.headers['WWW-Authenticate']).to be_nil
  end

  it 'maps discovery_metadata_invalid to 503 without WWW-Authenticate' do
    error = ::Verikloak::Error.new('discovery_metadata_invalid', 'bad')
    renderer.render(controller, error)
    expect(controller.rendered[:status]).to eq(503)
    expect(controller.response.headers['WWW-Authenticate']).to be_nil
  end

  it 'sanitizes values in WWW-Authenticate to prevent header injection' do
    error = ::Verikloak::Error.new('invalid_token', "bad\"\r\ndesc")
    renderer.render(controller, error)
    hdr = controller.response.headers['WWW-Authenticate']
    expect(hdr).to include('error="invalid_token"')
    # No newlines are allowed in header
    expect(hdr).not_to include("\r")
    expect(hdr).not_to include("\n")
    # Quote is escaped inside the quoted-string value; CR/LF collapsed to a single space
    expect(hdr).to include('error_description="bad\\" desc"')
  end
end
