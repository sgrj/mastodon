import React from 'react';
import { connect } from 'react-redux';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import DismissableBanner from 'mastodon/components/dismissable_banner';
import { setWorkshopActivity, setWorkshopInboxUrl } from 'mastodon/actions/activity_workshop';

import { ActivityWorkshop as Workshop } from 'activitypub-visualization';


const mapStateToProps = (state) => {
  return {
    activity: state.getIn(['activity_workshop', 'activity']),
    inboxUrl: state.getIn(['activity_workshop', 'inbox_url']),
    accessToken: state.getIn(['meta', 'access_token']),
  };
};

export default @connect(mapStateToProps)
class ActivityWorkshop extends ImmutablePureComponent {

  static propTypes = {
    dispatch: PropTypes.func.isRequired,
    multiColumn: PropTypes.bool,
  };

  handleHeaderClick = () => {
    this.column.scrollTop();
  };

  setRef = c => {
    this.column = c;
  };

  render() {

    const { dispatch, activity, inboxUrl, accessToken, multiColumn } = this.props;

    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label='Activity Workshop'>
        <ColumnHeader
          icon='wrench'
          title='Activity Workshop'
          onClick={this.handleHeaderClick}
          multiColumn={multiColumn}
        />

        <DismissableBanner id='activity_workshop'>
          <p>
            <FormattedMessage
              id='dismissable_banner.activity_workshop_information'
              defaultMessage='The Activity Workshop allows you to hand-craft your own activities and send them to inboxes of other actors. You can find more information on my {blog}.'
              values={{
                blog: <a className='blog-link' href='https://seb.jambor.dev/posts/activitypub-academy/'>blog</a>,
              }}
            />
          </p>
        </DismissableBanner>

        <div className={`h-full ${darkMode ? 'dark' : ''}`}>
          <Workshop
            activity={activity}
            inboxUrl={inboxUrl}
            onActivityChange={(activity) => dispatch(setWorkshopActivity(activity))}
            onInboxUrlChange={(inboxUrl) => dispatch(setWorkshopInboxUrl(inboxUrl))}
            onSubmit={async () =>
              fetch('/api/v1/activity', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` },
                body: JSON.stringify({ inbox_url: inboxUrl, activity: JSON.parse(activity) }),
              })
            }
          />
        </div>
      </Column>
    );
  }

}

