import PropTypes from 'prop-types';
import React from 'react';
import ImmutablePropTypes from 'react-immutable-proptypes';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { injectIntl } from 'react-intl';
import { connect } from 'react-redux';
import { createSelector } from 'reselect';

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
    logs: [],
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
    return <div>{this.state.logs.filter(x => x.type !== 'keep-alive').map(x => (<pre>{JSON.stringify(x, null, 2)}</pre>))}</div>;
  }

}
