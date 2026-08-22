# frozen_string_literal: true

require 'rails_helper'

# The Activity Workshop lets a student hand-craft an ActivityPub activity and have the
# instance sign and deliver it to any inbox, so they can see what a malformed or
# unusual activity does to a real receiving server.
describe 'Activity Workshop' do
  let(:user)      { Fabricate(:user) }
  let(:account)   { user.account }
  let(:token)     { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:headers)   { { 'Authorization' => "Bearer #{token.token}" } }
  let(:inbox_url) { 'https://remote.example/users/alice/inbox' }
  let(:activity) do
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'type' => 'Follow',
      'actor' => "https://#{Rails.configuration.x.web_domain}/users/#{account.username}",
      'object' => 'https://remote.example/users/alice',
    }
  end

  # rails_helper sets Sidekiq::Testing.inline!, which would actually perform the
  # delivery. We care about what gets handed to the worker.
  around do |example|
    Sidekiq::Testing.fake! { example.run }
  end

  describe 'POST /api/v1/activity' do
    it 'requires an authenticated user' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }

      expect(response).to have_http_status(422)
      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
    end

    it 'enqueues delivery of the activity as the current account' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }, headers: headers

      expect(response).to have_http_status(200)
      expect(ActivityPub::DeliveryWorker.jobs.size).to eq 1
    end

    it 'passes the activity through verbatim, the source account and the inbox' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }, headers: headers

      json, source_account_id, delivered_to = ActivityPub::DeliveryWorker.jobs.first['args']

      expect(Oj.load(json, mode: :strict)).to eq activity
      expect(source_account_id).to eq account.id
      expect(delivered_to).to eq inbox_url
    end

    it 'delivers a deliberately malformed activity, since that is the point' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: { 'type' => 'NotARealType' } }, headers: headers

      expect(response).to have_http_status(200)
      expect(Oj.load(ActivityPub::DeliveryWorker.jobs.first['args'].first, mode: :strict))
        .to eq('type' => 'NotARealType')
    end

    context 'with missing parameters' do
      it 'rejects a request with no inbox_url' do
        post '/api/v1/activity', params: { activity: activity }, headers: headers

        # Api::BaseController maps ActionController::ParameterMissing to 400.
        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end

      it 'rejects a request with no activity' do
        post '/api/v1/activity', params: { inbox_url: inbox_url }, headers: headers

        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end
    end
  end
end
