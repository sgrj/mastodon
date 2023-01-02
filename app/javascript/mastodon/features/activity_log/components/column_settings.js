import React from 'react';
import PropTypes from 'prop-types';
import { FormattedMessage } from 'react-intl';
import Icon from 'mastodon/components/icon';

export default function ColumnSettings({ clearLog }) {

  return (
    <div>
      <div className='column-settings__row'>
        <button className='text-btn column-header__setting-btn' tabIndex='0' onClick={clearLog}>
          <Icon id='eraser' />
          <FormattedMessage id='activity_log.clear' defaultMessage='Clear log' />
        </button>
      </div>
      <div role='group' aria-labelledby='activity-log-display-level'>
        <span id='activity-log-display-level' className='column-settings__section'>
          <FormattedMessage id='activity_log.display_level' defaultMessage='Show activities' />
        </span>

        <div className='column-settings__row' style={{ display: 'flex', flexDirection: 'column' }}>
          <label for='show_mine'>
            <input type='radio' name='test' id='show_mine' checked />
            Show only activities related to me
          </label>
          <label for='show_additional'>
            <input type='radio' name='test' id='show_additional' />
            Also show activities from the following actors:
          </label>
          <label for='show_all'>
            <input type='radio' name='test' id='show_all' />
            Show all activities
          </label>
        </div>
      </div>
    </div>
  );
}

ColumnSettings.propTypes = {
  clearLog: PropTypes.func.isRequired,
};
