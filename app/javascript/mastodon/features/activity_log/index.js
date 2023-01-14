import React, { useEffect, useReducer, useRef } from 'react';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import { HotKeys } from 'react-hotkeys';
import DismissableBanner from 'mastodon/components/dismissable_banner';

import ActivityPubVisualization from 'activitypub-visualization';

export default function ActivityLog({ multiColumn }) {

  const [logs, dispatch] = useReducer((state, [type, data]) => {
    switch (type) {
    case 'add-log-event':
      return [...state, data];
    case 'reset-logs':
      return [];
    default:
      return state;
    }
  }, []);

  const columnElement = useRef(null);

  useEffect(() => {
    const eventSource = new EventSource('/api/v1/activity_log');
    eventSource.onmessage = (event) => {
      const parsed = JSON.parse(event.data);
      if (parsed.type !== 'keep-alive') {
        dispatch(['add-log-event', parsed]);
      }
    };

    return function() {
      eventSource.close();
    };
  }, []);

  const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

  // hijack the toggleHidden shortcut to copy the logs to clipbaord
  const handlers = {
    toggleHidden: () => navigator.clipboard.writeText(JSON.stringify(logs, null, 2)),
  };

  return (
    <Column bindToDocument={!multiColumn} ref={columnElement} label='Activity Log'>
      <ColumnHeader
        icon='comments'
        title='Activity Log'
        onClick={() => { columnElement.current.scrollTop() }}
        multiColumn={multiColumn}
      />

      <DismissableBanner id='activity_log'>
        <p>
          <FormattedMessage
            id='dismissable_banner.activity_log_information'
            defaultMessage='Open Mastodon in another tab and interact with another instance (for example, follow an account on another instance). The resulting Activities will be shown here. You can find more information on my {blog}.'
            values={{
              blog: <a href='//seb.jambor.dev/' style={{ color: darkMode ? '#8c8dff' : '#3a3bff', textDecoration: 'none' }}>blog</a>,
            }}
          />
        </p>
        <p style={{ paddingTop: '5px' }}>
          <FormattedMessage
            id='dismissable_banner.activity_log_clear'
            defaultMessage='Note: Activities will only be logged while this view is open. When you navigate elsewhere, the log will be cleared.'
          />
        </p>
      </DismissableBanner>

      <HotKeys handlers={handlers}>
        <div className={`${darkMode ? 'dark' : ''}`}>
          <ActivityPubVisualization logs={logs} />
        </div>
      </HotKeys>

    </Column>
  );
}

ActivityLog.propTypes = {
  multiColumn: PropTypes.bool,
};
