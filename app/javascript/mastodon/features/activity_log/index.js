import React from 'react';
import { connect } from 'react-redux';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import { HotKeys } from 'react-hotkeys';
import { setExplorerData, setExplorerUrl } from 'mastodon/actions/activitypub_explorer';
import DismissableBanner from 'mastodon/components/dismissable_banner';

import { ActivityPubVisualization } from 'activitypub-visualization';

const mapStateToProps = (state) => {
  return {
    logs: state.getIn(['activity_log', 'logs']),
  };
};

export default @connect(mapStateToProps)
class ActivityLog extends ImmutablePureComponent {

  static contextTypes = {
    router: PropTypes.object,
  };

  static propTypes = {
    dispatch: PropTypes.func.isRequired,
    multiColumn: PropTypes.bool,
  };

  handleHeaderClick = () => {
    this.column.scrollTop();
  }

  setRef = c => {
    this.column = c;
  }

  render() {

    const { dispatch, logs, multiColumn } = this.props;

    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    // hijack the toggleHidden shortcut to copy the logs to clipbaord
    const handlers = {
      toggleHidden: () => navigator.clipboard.writeText(JSON.stringify(logs, null, 2)),
    };

    const Content = () => {
      if (logs.length > 0) {
        return ( <HotKeys handlers={handlers}>
          <div className={`${darkMode ? 'dark' : ''}`} style={{height: '100%'}}>
            <ActivityPubVisualization
              logs={logs}
              clickableLinks
              onLinkClick={(url) => {
                dispatch(setExplorerUrl(url));
                this.context.router.history.push('/activitypub_explorer');
              }}
              showExplorerLink
              onExplorerLinkClick={(data) => {
                dispatch(setExplorerData(data));
                this.context.router.history.push('/activitypub_explorer');
              }}
            />
          </div>
        </HotKeys>) } else {
          return (<div className='empty-column-indicator'>
            <FormattedMessage id='empty_column.activity_log' defaultMessage='The Activity Log is empty. Interact with accounts on other instances to trigger activities. You can find more information on my {blog}.'
              values={{
                blog: <a className='blog-link' href='https://seb.jambor.dev/posts/activitypub-academy/'>blog</a>,
              }}
            />
          </div>)
        }
    }

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label='Activity Log'>
        <ColumnHeader
          icon='comments'
          title='Activity Log'
          onClick={this.handleHeaderClick}
          multiColumn={multiColumn}
        />

        <DismissableBanner id='activity_log'>
          <p>
            <FormattedMessage
              id='dismissable_banner.activity_log_information'
              defaultMessage='When you interact with another instance (for example, follow an account on another instance), the resulting Activities will be shown here. You can find more information on my {blog}.'
              values={{
                blog: <a className='blog-link' href='https://seb.jambor.dev/posts/activitypub-academy/'>blog</a>,
              }}
            />
          </p>
          <p style={{ paddingTop: '5px' }}>
            <FormattedMessage
              id='dismissable_banner.activity_log_clear'
              defaultMessage='Note: Activities will only be logged while Mastodon is open. When you navigate elsewhere or reload the page, the log will be cleared.'
            />
          </p>
        </DismissableBanner>

        <Content />
      </Column>
    );
  }

}
