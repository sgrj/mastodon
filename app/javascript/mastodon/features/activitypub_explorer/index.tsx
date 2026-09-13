import { useCallback, useEffect, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { ActivityPubExplorer as Explorer } from 'activitypub-visualization';

import FindInPageIcon from '@/material-icons/400-24px/find_in_page.svg?react';
import { resetExplorer } from 'mastodon/actions/activitypub_explorer';
import { ACADEMY_POST_URL, BlogLink } from 'mastodon/components/blog_link';
import { Column } from 'mastodon/components/column';
import type { ColumnRef } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { DismissableBanner } from 'mastodon/components/dismissable_banner';
import { useTheme } from 'mastodon/hooks/useTheme';
import { getAccessToken } from 'mastodon/initial_state';
import { useAppDispatch, useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  heading: {
    id: 'column.activitypub_explorer',
    defaultMessage: 'ActivityPub Explorer',
  },
});

// `GET /api/v1/json_ld?url=...` proxies a signed fetch and hands the raw response
// straight back -- status, headers and body untouched. The library wants the
// `Response` itself (it reads `status`, `statusText` and calls `json()`), so this
// cannot go through `mastodon/api`, which is axios and has already unwrapped it,
// and which throws on exactly the statuses the Explorer exists to show. Hence a
// bare `fetch`, and the one place the bearer token is attached by hand.
//
// The header is omitted rather than sent empty when there is no token: the
// endpoint is `require_user!`, and same-origin session auth answers it too.
const fetchJsonLd = async (url: string) => {
  const accessToken = getAccessToken();

  return fetch(`/api/v1/json_ld?${new URLSearchParams({ url }).toString()}`, {
    headers: accessToken ? { Authorization: `Bearer ${accessToken}` } : {},
  });
};

const ExplorerContent: React.FC = () => {
  const dispatch = useAppDispatch();
  const darkMode = useTheme() === 'dark';

  // Read once, on mount. These are seeds for the library's own internal history:
  // it takes `initialUrl` / `initialActivityJson` in a mount-time effect and owns
  // every fetch after that, so re-rendering with a new value would do nothing.
  const initialUrl = useAppSelector((state) => state.activitypub_explorer.url);
  const initialData = useAppSelector(
    (state) => state.activitypub_explorer.data,
  );

  // Cleared on the way out, so arriving here from the nav link never resurrects
  // whatever the Activity Log last handed over.
  useEffect(
    () => () => {
      dispatch(resetExplorer());
    },
    [dispatch],
  );

  return (
    <div className={darkMode ? 'dark' : undefined}>
      <Explorer
        fetchMethod={fetchJsonLd}
        initialUrl={initialUrl}
        initialActivityJson={initialData}
      />
    </div>
  );
};

const ActivityPubExplorer: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const intl = useIntl();

  const columnRef = useRef<ColumnRef>(null);
  const handleHeaderClick = useCallback(() => {
    columnRef.current?.scrollTop();
  }, []);

  return (
    <Column
      bindToDocument={!multiColumn}
      ref={columnRef}
      label={intl.formatMessage(messages.heading)}
    >
      <ColumnHeader
        icon='wpexplorer'
        iconComponent={FindInPageIcon}
        title={intl.formatMessage(messages.heading)}
        onClick={handleHeaderClick}
        multiColumn={multiColumn}
      />

      <DismissableBanner id='activitypub_explorer'>
        <p>
          <FormattedMessage
            id='dismissable_banner.activitypub_explorer_information'
            defaultMessage='The ActivityPub Explorer provides a convenient way to browse through ActivityPub data. Click on any {https} URL in the returned JSON to fetch the corresponding data. You can find more information on my {blog}.'
            values={{
              blog: <BlogLink href={ACADEMY_POST_URL} />,
              https: <code>https://</code>,
            }}
          />
        </p>
      </DismissableBanner>

      <ExplorerContent />

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ActivityPubExplorer;
