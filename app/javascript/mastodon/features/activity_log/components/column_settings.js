import React from 'react';
import PropTypes from 'prop-types';
import { FormattedMessage } from 'react-intl';
import Icon from 'mastodon/components/icon';

export default class ColumnSettings extends React.PureComponent {

  static propTypes = {
    clearLog: PropTypes.func.isRequired,
  };

  render () {
    return (
      <div>
        <div className='column-settings__row'>
          <button className='text-btn column-header__setting-btn' tabIndex='0' onClick={this.props.clearLog}><Icon id='eraser' /> <FormattedMessage id='activity_log.clear' defaultMessage='Clear log' /></button>
        </div>
      </div>
    );
  }

}
