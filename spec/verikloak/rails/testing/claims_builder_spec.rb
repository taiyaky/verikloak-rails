# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'
require 'verikloak/rails/testing/claims_builder'

RSpec.describe Verikloak::Rails::Testing::ClaimsBuilder do
  let(:helper) { Class.new { include Verikloak::Rails::Testing::ClaimsBuilder }.new }

  let(:user) do
    OpenStruct.new(
      uid: 'user-123',
      email: 'alice@example.com',
      username: 'alice',
      first_name: 'Alice',
      last_name: 'Liddell'
    )
  end

  describe '#build_jwt_claims' do
    it 'returns OIDC-shaped claims with string keys' do
      claims = helper.build_jwt_claims(user)
      expect(claims['sub']).to eq('user-123')
      expect(claims['email']).to eq('alice@example.com')
      expect(claims['preferred_username']).to eq('alice')
      expect(claims['given_name']).to eq('Alice')
      expect(claims['family_name']).to eq('Liddell')
      expect(claims['groups']).to eq([])
      expect(claims['realm_access']).to eq('roles' => [])
      expect(claims['resource_access']).to eq({})
      expect(claims['aud']).to eq(['account'])
    end

    it 'falls back to email when username/preferred_username are missing' do
      bare = OpenStruct.new(uid: 'u', email: 'bob@example.com')
      claims = helper.build_jwt_claims(bare)
      expect(claims['preferred_username']).to eq('bob@example.com')
      expect(claims).not_to have_key('given_name')
      expect(claims).not_to have_key('family_name')
    end

    it 'uses preferred_username when username is absent' do
      u = OpenStruct.new(uid: 'u', email: 'p@example.com', preferred_username: 'pref')
      expect(helper.build_jwt_claims(u)['preferred_username']).to eq('pref')
    end

    it 'merges extra_claims with string keys, overriding base values' do
      claims = helper.build_jwt_claims(
        user,
        groups: ['/g1'],
        extra_claims: { aud: 'rails-api', custom: 'x' }
      )
      expect(claims['aud']).to eq('rails-api')
      expect(claims['custom']).to eq('x')
      expect(claims['groups']).to eq(['/g1'])
    end
  end

  describe '#build_admin_claims' do
    it 'sets the admin group' do
      expect(helper.build_admin_claims(user)['groups']).to eq(['/admin'])
    end

    it 'allows overriding the admin group' do
      expect(helper.build_admin_claims(user, admin_group: '/ops')['groups']).to eq(['/ops'])
    end
  end

  describe '#build_user_claims' do
    it 'sets the user group' do
      expect(helper.build_user_claims(user)['groups']).to eq(['/user'])
    end
  end
end
