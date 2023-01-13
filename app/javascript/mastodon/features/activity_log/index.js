import React, { useEffect, useReducer, useRef } from 'react';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import { HotKeys } from 'react-hotkeys';

import dummy_data from './dummy-data.json';

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
  // }, dummy_data);
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
    <HotKeys handlers={handlers}>
      <Column bindToDocument={!multiColumn} ref={columnElement} label='Activity Log'>
        <ColumnHeader
          icon='comments'
          title='Activity Log'
          onClick={() => { columnElement.current.scrollTop() }}
          multiColumn={multiColumn}
        />

        {/* <button onClick={() => navigator.clipboard.writeText(JSON.stringify(logs, null, 2))}>Copy logs</button> */}
        {/* <button onClick={() => dispatch(['reset-logs'])}>Clear logs</button> */}

        <div className={`${darkMode ? 'dark' : ''}`}>
          <ActivityPubVisualization logs={logs} />
        </div>

      </Column>
    </HotKeys>
  );
}

ActivityLog.propTypes = {
  multiColumn: PropTypes.bool,
};
