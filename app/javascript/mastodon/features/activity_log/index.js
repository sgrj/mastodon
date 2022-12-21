import PropTypes from 'prop-types';
import React from 'react';
import ImmutablePropTypes from 'react-immutable-proptypes';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { injectIntl } from 'react-intl';
import { connect } from 'react-redux';
import { createSelector } from 'reselect';

import ActivityPubVisualization from 'activity-pub-visualization';

const getOrderedLists = createSelector([state => state.get('lists')], lists => {
  if (!lists) {
    return lists;
  }

  return lists.toList().filter(item => !!item).sort((a, b) => a.get('title').localeCompare(b.get('title')));
});

const mapStateToProps = state => ({
  lists: getOrderedLists(state),
});

export default @connect(mapStateToProps)
@injectIntl
class Lists extends ImmutablePureComponent {

  static propTypes = {
    params: PropTypes.object.isRequired,
    dispatch: PropTypes.func.isRequired,
    lists: ImmutablePropTypes.list,
    intl: PropTypes.object.isRequired,
    multiColumn: PropTypes.bool,
  };

  state = {
    logs: [
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "inbound",
        "path": "/users/admin/inbox",
        "data": {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://techhub.social/users/crepels#follows/410930/undo",
          "type": "Undo",
          "actor": "https://techhub.social/users/crepels",
          "object": {
            "id": "https://techhub.social/bba308ce-f0e1-49af-9aa0-30d92e4ff71e",
            "type": "Follow",
            "actor": "https://techhub.social/users/crepels",
            "object": "https://localhost.jambor.dev/users/admin"
          }
        }
      },
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "inbound",
        "path": "/users/admin/inbox",
        "data": {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://techhub.social/a5f25e0a-98d6-4e5c-baad-65318cd4d67d",
          "type": "Follow",
          "actor": "https://techhub.social/users/crepels",
          "object": "https://localhost.jambor.dev/users/admin"
        }
      },
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "outbound",
        "path": "https://techhub.social/users/crepels/inbox",
        "data": {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://localhost.jambor.dev/users/admin#accepts/follows/29",
          "type": "Accept",
          "actor": "https://localhost.jambor.dev/users/admin",
          "object": {
            "id": "https://techhub.social/a5f25e0a-98d6-4e5c-baad-65318cd4d67d",
            "type": "Follow",
            "actor": "https://techhub.social/users/crepels",
            "object": "https://localhost.jambor.dev/users/admin"
          }
        }
      },
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "inbound",
        "path": "/inbox",
        "data": {
          "@context": [
            "https://www.w3.org/ns/activitystreams",
            {
              "ostatus": "http://ostatus.org#",
              "atomUri": "ostatus:atomUri",
              "inReplyToAtomUri": "ostatus:inReplyToAtomUri",
              "conversation": "ostatus:conversation",
              "sensitive": "as:sensitive",
              "toot": "http://joinmastodon.org/ns#",
              "votersCount": "toot:votersCount"
            }
          ],
          "id": "https://techhub.social/users/crepels/statuses/109473290785654613/activity",
          "type": "Create",
          "actor": "https://techhub.social/users/crepels",
          "published": "2022-12-07T16:17:32Z",
          "to": [
            "https://localhost.jambor.dev/users/admin"
          ],
          "cc": [],
          "object": {
            "id": "https://techhub.social/users/crepels/statuses/109473290785654613",
            "type": "Note",
            "summary": null,
            "inReplyTo": null,
            "published": "2022-12-07T16:17:32Z",
            "url": "https://techhub.social/@crepels/109473290785654613",
            "attributedTo": "https://techhub.social/users/crepels",
            "to": [
              "https://localhost.jambor.dev/users/admin"
            ],
            "cc": [],
            "sensitive": false,
            "atomUri": "https://techhub.social/users/crepels/statuses/109473290785654613",
            "inReplyToAtomUri": null,
            "conversation": "tag:techhub.social,2022-12-07:objectId=5564498:objectType=Conversation",
            "content": "<p><span class=\"h-card\"><a href=\"https://localhost.jambor.dev/@admin\" class=\"u-url mention\">@<span>admin</span></a></span> test</p>",
            "contentMap": {
              "en": "<p><span class=\"h-card\"><a href=\"https://localhost.jambor.dev/@admin\" class=\"u-url mention\">@<span>admin</span></a></span> test</p>"
            },
            "attachment": [],
            "tag": [
              {
                "type": "Mention",
                "href": "https://localhost.jambor.dev/users/admin",
                "name": "@admin@localhost.jambor.dev"
              }
            ],
            "replies": {
              "id": "https://techhub.social/users/crepels/statuses/109473290785654613/replies",
              "type": "Collection",
              "first": {
                "type": "CollectionPage",
                "next": "https://techhub.social/users/crepels/statuses/109473290785654613/replies?only_other_accounts=true&page=true",
                "partOf": "https://techhub.social/users/crepels/statuses/109473290785654613/replies",
                "items": []
              }
            }
          }
        }
      },
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "inbound",
        "path": "/users/admin/inbox",
        "data": {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://techhub.social/users/crepels#likes/263597",
          "type": "Like",
          "actor": "https://techhub.social/users/crepels",
          "object": "https://localhost.jambor.dev/users/admin/statuses/109461738015823934"
        }
      },
      {
        "timestamp":"2022-12-08T17:12:38Z",
        "type": "inbound",
        "path": "/users/admin/inbox",
        "data": {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://techhub.social/users/crepels#likes/263597/undo",
          "type": "Undo",
          "actor": "https://techhub.social/users/crepels",
          "object": {
            "id": "https://techhub.social/users/crepels#likes/263597",
            "type": "Like",
            "actor": "https://techhub.social/users/crepels",
            "object": "https://localhost.jambor.dev/users/admin/statuses/109461738015823934"
          }
        }
      }
    ],
  };


  componentDidMount() {
    this.eventSource = new EventSource('/api/v1/activity_log');
    this.eventSource.onmessage = (event) => {
      this.setState({ logs: [...this.state.logs, JSON.parse(event.data)] });
    };
  }

  componentWillUnmount() {
    if (this.eventSource) {
      this.eventSource.close();
    }
  }

  render () {
    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    return (<div className={`${darkMode ? 'dark' : ''}`}>
      <ActivityPubVisualization logs={this.state.logs} />
    </div>);
  }

}
