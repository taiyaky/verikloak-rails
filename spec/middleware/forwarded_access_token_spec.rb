# frozen_string_literal: true

require 'spec_helper'


RSpec.describe Verikloak::Rails::MiddlewareIntegration::ForwardedAccessToken do
  let(:app) do
    Class.new do
      attr_reader :last_env
      def call(env)
        @last_env = env
        [200, { 'Content-Type' => 'text/plain' }, ['ok']]
      end
    end.new
  end

  def call_mw(env, trust: false, proxies: [], priority: %w[HTTP_X_FORWARDED_ACCESS_TOKEN HTTP_AUTHORIZATION])
    mw = described_class.new(app, trust_forwarded: trust, trusted_proxies: proxies, header_priority: priority)
    status, headers, body = mw.call(env)
    { status: status, headers: headers, body: body, env: app.last_env }
  end

  let(:trusted_subnet) { IPAddr.new('10.0.0.0/8') }

  it 'promotes X-Forwarded-Access-Token when trusted and Authorization missing' do
    result = call_mw({
      'REMOTE_ADDR' => '10.0.0.1',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123'
    }, trust: true, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to eq('Bearer abc123')
  end

  it 'does not override existing Authorization' do
    result = call_mw({
      'REMOTE_ADDR' => '10.0.0.1',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123',
      'HTTP_AUTHORIZATION' => 'Bearer original'
    }, trust: true, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to eq('Bearer original')
  end

  it 'does not promote forwarded token when untrusted (trust disabled)' do
    result = call_mw({
      'REMOTE_ADDR' => '203.0.113.10',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123'
    }, trust: false, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to be_nil
  end

  it 'does not promote forwarded token when from non-trusted IP' do
    result = call_mw({
      'REMOTE_ADDR' => '203.0.113.10',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123'
    }, trust: true, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to be_nil
  end

  it 'promotes first non-Authorization header in priority and prefixes Bearer if needed' do
    result = call_mw({
      'REMOTE_ADDR' => '203.0.113.10',
      'HTTP_CUSTOM_TOKEN' => 'xyz',
    }, trust: false, proxies: [], priority: %w[HTTP_CUSTOM_TOKEN HTTP_AUTHORIZATION])

    expect(result[:env]['HTTP_AUTHORIZATION']).to eq('Bearer xyz')
  end

  it 'respects X-Forwarded-For fallback when REMOTE_ADDR is empty' do
    result = call_mw({
      'REMOTE_ADDR' => '',
      'HTTP_X_FORWARDED_FOR' => '198.51.100.5, 10.0.0.2',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123'
    }, trust: true, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to eq('Bearer abc123')
  end

  it 'does not duplicate Bearer prefix' do
    result = call_mw({
      'REMOTE_ADDR' => '203.0.113.10',
      'HTTP_CUSTOM_TOKEN' => 'Bearer token',
    }, trust: false, proxies: [], priority: %w[HTTP_CUSTOM_TOKEN HTTP_AUTHORIZATION])

    expect(result[:env]['HTTP_AUTHORIZATION']).to eq('Bearer token')
  end

  it 'does not promote when IP addresses are invalid' do
    result = call_mw({
      'REMOTE_ADDR' => 'not-an-ip',
      'HTTP_X_FORWARDED_FOR' => 'also-not-an-ip',
      'HTTP_X_FORWARDED_ACCESS_TOKEN' => 'abc123'
    }, trust: true, proxies: [trusted_subnet])

    expect(result[:env]['HTTP_AUTHORIZATION']).to be_nil
  end
end
