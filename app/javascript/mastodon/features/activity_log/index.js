import React from 'react';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';

import dummy_data from './dummy-data.json';

import ColumnSettings from './components/column_settings';

import ActivityPubVisualization from 'activity-pub-visualization';

export default class ActivityLog extends React.PureComponent {

  state = {
    logs: dummy_data,
  };

  static propTypes = {
    multiColumn: PropTypes.bool,
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

  handleHeaderClick = () => {
    this.column.scrollTop();
  }

  clearLog = () => {
    this.setState({ logs: [] });
  }

  render () {
    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    const { multiColumn } = this.props;

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label='Activity Log'>
        <ColumnHeader
          icon='comments'
          title='Activity Log'
          onClick={this.handleHeaderClick}
          multiColumn={multiColumn}
        >
          <ColumnSettings clearLog={this.clearLog} />
        </ColumnHeader>

        <div className={`${darkMode ? 'dark' : ''}`}>
          <ActivityPubVisualization logs={this.state.logs} />
        </div>

      </Column>
    );
  }

}
