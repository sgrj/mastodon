import { PureComponent } from 'react';

import { Helmet } from '@unhead/react/helmet';
import { Route } from 'react-router-dom';

import { Provider as ReduxProvider } from 'react-redux';

import { addActivityLog, resetActivityLog } from 'mastodon/actions/activity_log';
import { hydrateStore } from 'mastodon/actions/store';
import { connectUserStream } from 'mastodon/actions/streaming';
import ErrorBoundary from 'mastodon/components/error_boundary';
import { FocusTargetProvider } from '@/mastodon/components/navigation_focus_target';
import { Router } from 'mastodon/components/router';
import UI from 'mastodon/features/ui';
import { IdentityContext, createIdentityContext } from 'mastodon/identity_context';
import { initialState, title as siteTitle } from 'mastodon/initial_state';
import { IntlProvider } from 'mastodon/locales';
import { store } from 'mastodon/store';
import { isProduction } from 'mastodon/utils/environment';
import { BodyScrollLock } from 'mastodon/features/ui/components/body_scroll_lock';

import { ScrollContext } from './scroll_container/scroll_context';

const title = isProduction() ? siteTitle : `${siteTitle} (Dev)`;

const hydrateAction = hydrateStore(initialState);

store.dispatch(hydrateAction);

export default class Mastodon extends PureComponent {
  identity = createIdentityContext(initialState);

  componentDidMount() {
    if (this.identity.signedIn) {
      this.disconnect = store.dispatch(connectUserStream());

      // The Activity Log is a second, independent stream: `GET /api/v1/activity_log`
      // hijacks the Rack socket and writes server-sent events for every activity
      // this account sends or receives. It is opened here rather than in the
      // column so that activities triggered while the student is looking at a
      // timeline are still there when they switch to the log -- the store is the
      // buffer, and it only lives as long as the page does.
      this.eventSource = new EventSource('/api/v1/activity_log');
      this.eventSource.onmessage = (event) => {
        const parsed = JSON.parse(event.data);

        // Keep-alives exist to stop a proxy closing an idle connection
        // (ActivityLogger::KEEP_ALIVE_INTERVAL); they are not log entries.
        if (parsed.type !== 'keep-alive') {
          store.dispatch(addActivityLog(parsed));
        }
      };
    }
  }

  componentWillUnmount () {
    if (this.disconnect) {
      this.disconnect();
      this.disconnect = null;
    }

    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
      store.dispatch(resetActivityLog());
    }
  }

  render () {
    return (
      <IdentityContext.Provider value={this.identity}>
        <IntlProvider>
          <ReduxProvider store={store}>
            <ErrorBoundary>
              <Router>
                <ScrollContext>
                  <FocusTargetProvider>
                    <Route path='/' component={UI} />
                  </FocusTargetProvider>
                </ScrollContext>
                <BodyScrollLock />
              </Router>

              <Helmet defaultTitle={title} titleTemplate={`%s - ${title}`} />
            </ErrorBoundary>
          </ReduxProvider>
        </IntlProvider>
      </IdentityContext.Provider>
    );
  }

}
