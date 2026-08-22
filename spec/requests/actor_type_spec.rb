# frozen_string_literal: true

require 'rails_helper'

# The fork lets students change their own actor type from the profile settings page,
# so they can watch how remote instances react to a Person becoming a Service or a
# Group. ActivityPub::ActorSerializer#type therefore returns the stored column instead
# of deriving the type the way upstream does.
describe 'Actor type' do
  let(:headers) { { 'Accept' => 'application/activity+json' } }

  def actor_type_for(account)
    get account_url(account), headers: headers
    body_as_json[:type]
  end

  describe 'the ActivityPub actor document' do
    %w(Person Service Group Organization Application).each do |type|
      it "serializes an account stored as #{type} with that type" do
        account = Fabricate(:account, username: "a_#{type.downcase}", actor_type: type)

        expect(actor_type_for(account)).to eq type
      end
    end

    # Upstream derives the type and always emits one of Application/Service/Group/
    # Person. actor_type is nullable, so returning the column verbatim can emit
    # "type": null, which is not a valid ActivityPub actor.
    it 'never serializes a null type' do
      account = Fabricate(:account, username: 'no_type', actor_type: nil)

      expect(actor_type_for(account)).to eq 'Person'
    end

    # The instance actor is served from /actor, not /users/:username -- its username
    # contains a dot, which the :username route segment would read as a format.
    it 'still presents the instance actor as an Application' do
      get instance_actor_url, headers: headers

      expect(body_as_json[:type]).to eq 'Application'
    end
  end

  describe 'PUT /settings/profile' do
    let(:user) { Fabricate(:user) }

    before { sign_in user }

    it 'lets a user change their own actor type' do
      expect { put settings_profile_path, params: { account: { actor_type: 'Service' } } }
        .to change { user.account.reload.actor_type }.to('Service')
    end

    it 'is reflected in the actor document that remote instances fetch' do
      put settings_profile_path, params: { account: { actor_type: 'Group' } }

      expect(actor_type_for(user.account.reload)).to eq 'Group'
    end
  end
end
