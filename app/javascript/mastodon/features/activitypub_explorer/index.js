import React from 'react';
import { connect } from 'react-redux';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import DismissableBanner from 'mastodon/components/dismissable_banner';
import { setExplorerData } from 'mastodon/actions/activitypub_explorer';

import { ActivityPubExplorer as Explorer } from 'activitypub-visualization';


const mapStateToProps = (state) => {
  return {
    data: state.getIn(['activitypub_explorer', 'data']),
  };
};

export default @connect(mapStateToProps)
class ActivityPubExplorer extends ImmutablePureComponent {

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

  componentWillMount () {
    // clear explorer data on unbound so that we start with a clean slate on next navigation
    this.props.dispatch(setExplorerData(null));
  }

  render() {

    const { data, multiColumn } = this.props;

    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label='ActivityPub Explorer'>
        <ColumnHeader
          icon='wpexplorer'
          title='ActivityPub Explorer'
          onClick={this.handleHeaderClick}
          multiColumn={multiColumn}
        />

        <DismissableBanner id='activity_log'>
          <p>
            <FormattedMessage
              id='dismissable_banner.activity_pub_explorer_information'
              defaultMessage='TODO. You can find more information on my {blog}.'
              values={{
                blog: <a href='//seb.jambor.dev/' style={{ color: darkMode ? '#8c8dff' : '#3a3bff', textDecoration: 'none' }}>blog</a>,
              }}
            />
          </p>
        </DismissableBanner>

        <div className={`${darkMode ? 'dark' : ''}`}>
          <Explorer initialValue={data} />
        </div>
      </Column>
    );
  }

}

