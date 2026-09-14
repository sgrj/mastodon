# frozen_string_literal: true

require 'rails_helper'

# The fork lets students change their own actor type, so they can watch how remote
# instances react to a Person becoming a Service or a Group. Upstream *derives* the
# ActivityPub type from flags (bot? -> Service, group? -> Group, else Person);
# ActivityPub::ActorSerializer#type here returns the stored column instead, and
# `actor_type` is permitted on both write paths so the profile editor can set it:
# PATCH /api/v1/accounts/update_credentials (the fork-era API) and PATCH /api/v1/profile
# (the endpoint v4.7's React profile editor actually talks to, which did not exist when
# the fork was written). REST::ProfileSerializer exposes the column so the editor's
# <select> can show the current value.
RSpec.describe 'Actor type' do
  def actor_type_at(path)
    get path, headers: { 'Accept' => 'application/activity+json' }

    response.parsed_body[:type]
  end

  describe 'the ActivityPub actor document' do
    %w(Person Service Group Organization Application).each do |type|
      it "serializes an account stored as #{type} with that type" do
        account = Fabricate(:account, username: "a_#{type.downcase}", actor_type: type)

        expect(actor_type_at(account_path(account))).to eq type
      end
    end

    # Nothing validates the column, which is the point: the lesson includes watching
    # remote servers meet a type they do not know.
    it 'serializes an unrecognised actor type verbatim' do
      account = Fabricate(:account, username: 'a_teapot', actor_type: 'Teapot')

      expect(actor_type_at(account_path(account))).to eq 'Teapot'
    end

    # Upstream derives the type and always emits one of Application/Service/Group/
    # Person. actor_type is nullable, so returning the column verbatim can emit
    # "type": null, which is not a valid ActivityPub actor.
    it 'never serializes a null type' do
      account = Fabricate(:account, username: 'no_type', actor_type: nil)

      expect(actor_type_at(account_path(account))).to eq 'Person'
    end

    # The instance actor is served from /actor, not /users/:username -- its username
    # contains a dot, which the :username route segment would read as a format.
    it 'still presents the instance actor as an Application' do
      expect(actor_type_at(instance_actor_path)).to eq 'Application'
    end
  end

  describe 'PATCH /api/v1/accounts/update_credentials' do
    include_context 'with API authentication', oauth_scopes: 'write:accounts'

    it 'lets a user change their own actor type' do
      expect { patch '/api/v1/accounts/update_credentials', headers: headers, params: { actor_type: 'Service' } }
        .to change { user.account.reload.actor_type }.to('Service')

      expect(response).to have_http_status(200)
    end

    it 'is reflected in the actor document that remote instances fetch' do
      patch '/api/v1/accounts/update_credentials', headers: headers, params: { actor_type: 'Group' }

      expect(actor_type_at(account_path(user.account.reload))).to eq 'Group'
    end
  end

  # This is the endpoint app/javascript/mastodon/features/account_edit/index.tsx uses.
  describe '/api/v1/profile' do
    include_context 'with API authentication', oauth_scopes: 'read:accounts write:accounts'

    it 'exposes the stored actor type so the editor can preselect it' do
      user.account.update!(actor_type: 'Group')

      get '/api/v1/profile', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:actor_type]).to eq 'Group'
    end

    it 'exposes a null actor type rather than deriving one' do
      user.account.update!(actor_type: nil)

      get '/api/v1/profile', headers: headers

      expect(response.parsed_body[:actor_type]).to be_nil
    end

    it 'lets a user change their own actor type' do
      expect { patch '/api/v1/profile', headers: headers, params: { actor_type: 'Service' } }
        .to change { user.account.reload.actor_type }.to('Service')

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:actor_type]).to eq 'Service'
    end

    it 'accepts a type no ActivityPub vocabulary defines' do
      patch '/api/v1/profile', headers: headers, params: { actor_type: 'Teapot' }

      expect(user.account.reload.actor_type).to eq 'Teapot'
    end

    it 'is reflected in the actor document that remote instances fetch' do
      patch '/api/v1/profile', headers: headers, params: { actor_type: 'Organization' }

      expect(actor_type_at(account_path(user.account.reload))).to eq 'Organization'
    end

    # Account#bot= writes actor_type ('Service' or 'Person'), so the two params collide.
    # params.permit returns keys in filter-list order and :actor_type is listed after
    # :bot, so an explicit actor_type is applied last and wins. The React editor sends
    # only actor_type -- its bot toggle is gone -- but the ordering is load-bearing for
    # any other client that sends both.
    it 'applies an explicit actor type after bot= when a client sends both' do
      patch '/api/v1/profile', headers: headers, params: { bot: true, actor_type: 'Group' }

      expect(user.account.reload.actor_type).to eq 'Group'
    end
  end
end
