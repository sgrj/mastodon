import React from 'react';
import { connect } from 'react-redux';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';
import Column from 'mastodon/components/column';
import ColumnHeader from 'mastodon/components/column_header';
import DismissableBanner from 'mastodon/components/dismissable_banner';
import { me, domain } from 'mastodon/initial_state';

import { WebFingerForge as Forge } from 'activitypub-visualization';


const mapStateToProps = (state) => {
  return {
    accessToken: state.getIn(['meta', 'access_token']),
    account: state.getIn(['accounts', me]),
  };
};

export default @connect(mapStateToProps)
class WebFingerForge extends ImmutablePureComponent {

  static propTypes = {
    multiColumn: PropTypes.bool,
  };

  handleHeaderClick = () => {
    this.column.scrollTop();
  };

  setRef = c => {
    this.column = c;
  };

  render() {

    const { multiColumn, accessToken, account } = this.props;

    const darkMode = !(document.body && document.body.classList.contains('theme-mastodon-light'));

    return (
      <Column bindToDocument={!multiColumn} ref={this.setRef} label='WebFinger Forge'>
        <ColumnHeader
          icon='hand-pointer-o'
          title='WebFinger Forge'
          onClick={this.handleHeaderClick}
          multiColumn={multiColumn}
        />

        <DismissableBanner id='web_finger_forge'>
          <p>
            <FormattedMessage
              id='dismissable_banner.web_finger_forge_information'
              defaultMessage='The WebFinger Forge allows you to control the data that is returned when the web-finger endpoint for your actor is called. You can find more information on my {blog}.'
              values={{
                blog: <a className='blog-link' href='https://seb.jambor.dev/posts/activitypub-academy/'>blog</a>,
              }}
            />
          </p>
        </DismissableBanner>

        <div className={`h-full ${darkMode ? 'dark' : ''}`}>
          <Forge
            loadData={async () => {

              // const response = await fetch(`/.well-known/webfinger?resource=acct:${account.get('acct')}%40${domain}`);
              const response = await fetch('/api/v1/webfinger', {
                headers: { 'Accept': 'application/json', 'Authorization': `Bearer ${accessToken}` },
              });
              if (!response.ok) {
                throw new Error(`WebFinger response returned status ${response.status}`);
              }

              const body = await response.json();

              return JSON.stringify(body, null, 2);
            }}
            onSubmit={async (value) => {
              const response = await fetch('/api/v1/webfinger', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` },
                body: JSON.stringify({ value }),
              });

              if (!response.ok) {
                throw new Error(`WebFinger response returned status ${response.status}`);
              }
            }}
          />
        </div>
      </Column>
    );
  }

}

