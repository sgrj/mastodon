# frozen_string_literal: true

require 'rails_helper'

# The Activity Workshop lets a student hand-craft an ActivityPub activity and have the
# instance sign and deliver it to any inbox, so they can see what a malformed or
# unusual activity does to a real receiving server. Nothing here validates the
# activity; the whole point is that it does not.
#
# The SPA posts application/json (see the fork's activity_workshop component), so these
# examples use `as: :json` -- form encoding would stringify every scalar and flatten the
# nesting that the wildcard permit exists to preserve.
RSpec.describe 'Activity Workshop' do
  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:account)   { user.account }
  let(:inbox_url) { 'https://remote.example/users/alice/inbox' }

  let(:activity) do
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'type' => 'Follow',
      'actor' => ActivityPub::TagManager.instance.uri_for(account),
      'object' => 'https://remote.example/users/alice',
    }
  end

  # rspec-sidekiq puts Sidekiq::Testing in fake mode, so nothing is delivered for real.
  # What is asserted here is what gets handed to the worker.
  def enqueued_args
    ActivityPub::DeliveryWorker.jobs.first['args']
  end

  describe 'POST /api/v1/activity' do
    it 'requires an authenticated user' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }, as: :json

      expect(response).to have_http_status(422)
      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
    end

    it 'enqueues delivery of the activity as the current account' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(ActivityPub::DeliveryWorker.jobs.size).to eq 1
    end

    it 'passes the activity through verbatim, the source account and the inbox' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity }, headers: headers, as: :json

      # Exactly three arguments. ActivityPub::DeliveryWorker#perform gained a fourth
      # `options = {}` parameter upstream; it has a default, so the fork's three-arg
      # call is still the right shape and the worker sees `bypass_availability` unset.
      expect(enqueued_args.size).to eq 3

      json, source_account_id, delivered_to = enqueued_args

      expect(JSON.parse(json)).to eq activity
      expect(source_account_id).to eq account.id
      expect(delivered_to).to eq inbox_url
    end

    it 'preserves arbitrary nesting, arrays and JSON scalars through the wildcard permit' do
      nested = {
        '@context' => ['https://www.w3.org/ns/activitystreams', { 'academy' => 'https://example.com/ns#' }],
        'type' => 'Create',
        'object' => {
          'type' => 'Note',
          'content' => 'hello',
          'tag' => [
            { 'type' => 'Mention', 'href' => 'https://remote.example/users/alice' },
            { 'type' => 'Hashtag', 'name' => '#activitypub' },
          ],
          'academy' => { 'deeply' => { 'nested' => [1, true, { 'still' => 'here' }], 'null' => nil } },
        },
        'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      }

      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: nested }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(JSON.parse(enqueued_args.first)).to eq nested
    end

    it 'drops a null element inside an array -- the one thing it does not deliver verbatim' do
      # Not the wildcard permit, which keeps nils happily. ActionDispatch's
      # NoNilParamEncoder (`Request::Utils.perform_deep_munge`, on by default since
      # Rails 4) compacts every array in every request's parameters. A `null` as a hash
      # *value* survives; a `null` as an array *element* does not, so this is the single
      # shape of activity the Workshop cannot hand to a student's chosen inbox.
      activity_with_nulls = { 'type' => 'Create', 'to' => ['https://remote.example/users/alice', nil], 'object' => nil }

      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: activity_with_nulls }, headers: headers, as: :json

      expect(JSON.parse(enqueued_args.first))
        .to eq('type' => 'Create', 'to' => ['https://remote.example/users/alice'], 'object' => nil)
    end

    it 'drops parameters outside the filter list' do
      post '/api/v1/activity',
           params: { inbox_url: inbox_url, activity: activity, source_account_id: 1, admin: true },
           headers: headers,
           as: :json

      json, source_account_id, _delivered_to = enqueued_args

      expect(JSON.parse(json)).to eq activity
      expect(source_account_id).to eq account.id
    end

    it 'delivers a deliberately malformed activity, since that is the point' do
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: { 'type' => 'NotARealType' } }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(JSON.parse(enqueued_args.first)).to eq('type' => 'NotARealType')
    end

    it 'delivers an empty object when the activity is not an object at all' do
      # A bare string does not match the `activity: {}` filter, so permit drops it and
      # the delivered body is `{}`. The body handed to the worker is therefore always
      # syntactically valid JSON -- the Workshop cannot produce a body that a receiving
      # Rails 8 instance would reject with a 400 before its inbox controller runs.
      post '/api/v1/activity', params: { inbox_url: inbox_url, activity: 'this is not an object' }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(enqueued_args.first).to eq '{}'
    end

    context 'with missing parameters' do
      it 'rejects a request with no inbox_url' do
        post '/api/v1/activity', params: { activity: activity }, headers: headers, as: :json

        # Api::ErrorHandling maps ActionController::ParameterMissing to 400.
        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end

      it 'rejects a request with no activity' do
        post '/api/v1/activity', params: { inbox_url: inbox_url }, headers: headers, as: :json

        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end

      it 'does not let ParamsWrapper invent an activity out of the rest of the body' do
        # Without `wrap_parameters false` on the controller this is a 200 that signs and
        # delivers `{"inbox_url": "..."}` to the inbox, because the JSON wrapper key
        # derived from ActivityController is `activity`. See PORTING.md Surprise 31.
        post '/api/v1/activity', params: { inbox_url: inbox_url, note: 'hello' }, headers: headers, as: :json

        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end

      it 'rejects a request whose activity is an empty object' do
        post '/api/v1/activity', params: { inbox_url: inbox_url, activity: {} }, headers: headers, as: :json

        expect(response).to have_http_status(400)
        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end
    end
  end
end
