import React from 'react';
import { connect } from 'react-redux';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import DismissableBanner from 'mastodon/components/dismissable_banner';
import { setExplorerData, setExplorerUrl } from 'mastodon/actions/activitypub_explorer';

import { ActivityPubExplorer as Explorer } from 'activitypub-visualization';


const mapStateToProps = (state) => {
  return {
    data: state.getIn(['activitypub_explorer', 'data']),
    url: state.getIn(['activitypub_explorer', 'url']),
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

  componentWillUnmount () {
    // clear explorer data on unbound so that we start with a clean slate on next navigation
    this.props.dispatch(setExplorerData(null));
    this.props.dispatch(setExplorerUrl(''));
  }

  render() {

    const { data, url, multiColumn } = this.props;

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
              defaultMessage='The AcivityPub Explorer provides a convenient way to browse through ActivityPub data. Click on any {https} URL in the returned JSON to fetch the corresponding data. You can find more information on my {blog}.'
              values={{
                blog: <a className='blog-link' href='https://seb.jambor.dev/posts/activitypub-academy/'>blog</a>,
                https: <code>https://</code>,
              }}
            />
          </p>
        </DismissableBanner>

        <div className={`${darkMode ? 'dark' : ''}`}>
          <Explorer
            fetchMethod={async (url) =>
              fetch('/api/v1/json_ld?' + new URLSearchParams({ url }).toString())
            }
            initialActivityJson={data}
            initialUrl={url}
          />
        </div>
      </Column>
    );
  }

}

