import React, { useEffect, useReducer, useRef } from 'react';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';

import dummy_data from './dummy-data.json';

import ColumnSettings from './components/column_settings';

import ActivityPubVisualization from 'activity-pub-visualization';

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
  }, dummy_data);

  const columnElement = useRef(null);

  useEffect(() => {
    const eventSource = new EventSource('/api/v1/activity_log');
    eventSource.onmessage = (event) => {
      dispatch(['add-log-event', JSON.parse(event.data)]);
    };

    return function() {
      eventSource.close();
    };
  }, []);


  const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

  return (
    <Column bindToDocument={!multiColumn} ref={columnElement} label='Activity Log'>
      <ColumnHeader
        icon='comments'
        title='Activity Log'
        onClick={() => { columnElement.current.scrollTop() }}
        multiColumn={multiColumn}
      >
        <ColumnSettings clearLog={() => dispatch(['reset-logs'])} />
      </ColumnHeader>

      <div className={`${darkMode ? 'dark' : ''}`}>
        <ActivityPubVisualization logs={logs} />
      </div>

    </Column>
  );
}

ActivityLog.propTypes = {
  multiColumn: PropTypes.bool,
};
