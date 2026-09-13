import { useCallback, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { ActivityPubVisualization } from 'activitypub-visualization';

import CommentIcon from '@/material-icons/400-24px/comment.svg?react';
import {
  setWorkshopActivity,
  setWorkshopInboxUrl,
} from 'mastodon/actions/activity_workshop';
import {
  setExplorerData,
  setExplorerUrl,
} from 'mastodon/actions/activitypub_explorer';
import { ACADEMY_POST_URL, BlogLink } from 'mastodon/components/blog_link';
import { Column } from 'mastodon/components/column';
import type { ColumnRef } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { DismissableBanner } from 'mastodon/components/dismissable_banner';
import { useHotkeys } from 'mastodon/components/hotkeys';
import { useAppHistory } from 'mastodon/components/router';
import { useTheme } from 'mastodon/hooks/useTheme';
import type {
  ActivityLogActivity,
  ActivityLogEvent,
} from 'mastodon/models/activity_log';
import { useAppDispatch, useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  heading: { id: 'column.activity_log', defaultMessage: 'Activity Log' },
});

const ActivityLogStream: React.FC = () => {
  const logs = useAppSelector((state) => state.activity_log.logs);
  const darkMode = useTheme() === 'dark';
  const dispatch = useAppDispatch();
  const history = useAppHistory();

  // The three link-outs that make the log a starting point rather than a
  // read-only feed. Each one seeds the target column's slice of the store and
  // then pushes its route: both columns are code-split, so there is nothing to
  // call into until the route mounts them.
  //
  // A URL inside a rendered activity -- an actor, an object, a collection.
  const handleLinkClick = useCallback(
    (url: string) => {
      dispatch(setExplorerUrl(url));
      history.push('/activitypub_explorer');
    },
    [dispatch, history],
  );

  // "Open in Explorer" on a whole activity: no fetch, the JSON is already here.
  const handleExplorerLinkClick = useCallback(
    (data: ActivityLogActivity) => {
      dispatch(setExplorerData(data));
      history.push('/activitypub_explorer');
    },
    [dispatch, history],
  );

  // "Open in Workshop": the activity becomes the editor's text and the log
  // entry's path -- the inbox it was delivered to -- becomes the target, so a
  // student can replay a real exchange with one field changed.
  const handleWorkshopLinkClick = useCallback(
    (event: ActivityLogEvent) => {
      dispatch(setWorkshopActivity(JSON.stringify(event.data, null, 2)));
      dispatch(setWorkshopInboxUrl(event.path));
      history.push('/activity_workshop');
    },
    [dispatch, history],
  );

  // The fork hijacks the `toggleHidden` shortcut -- `x`, which has no meaning in
  // this column -- to copy the whole log to the clipboard, so a student can
  // paste an exchange somewhere else. react-hotkeys is gone; this is the same
  // trick against mastodon/components/hotkeys, whose useHotkeys returns a ref
  // that scopes the shortcut to the element it is attached to.
  const hotkeyRef = useHotkeys<HTMLDivElement>({
    toggleHidden: () => {
      void navigator.clipboard.writeText(JSON.stringify(logs, null, 2));
    },
  });

  if (logs.length === 0) {
    return (
      <div className='empty-column-indicator'>
        <FormattedMessage
          id='empty_column.activity_log'
          defaultMessage='The Activity Log is empty. Interact with accounts on other instances to trigger activities. You can find more information on my {blog}.'
          values={{ blog: <BlogLink href={ACADEMY_POST_URL} /> }}
        />
      </div>
    );
  }

  return (
    <div
      ref={hotkeyRef}
      tabIndex={-1}
      className={darkMode ? 'dark' : undefined}
      style={{ height: '100%' }}
    >
      <ActivityPubVisualization
        logs={logs}
        clickableLinks
        onLinkClick={handleLinkClick}
        showExplorerLink
        onExplorerLinkClick={handleExplorerLinkClick}
        showWorkshopLink
        onWorkshopLinkClick={handleWorkshopLinkClick}
      />
    </div>
  );
};

const ActivityLog: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
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
        icon='comments'
        iconComponent={CommentIcon}
        title={intl.formatMessage(messages.heading)}
        onClick={handleHeaderClick}
        multiColumn={multiColumn}
      />

      <DismissableBanner id='activity_log'>
        <p>
          <FormattedMessage
            id='dismissable_banner.activity_log_information'
            defaultMessage='When you interact with another instance (for example, follow an account on another instance), the resulting Activities will be shown here. You can find more information on my {blog}.'
            values={{ blog: <BlogLink href={ACADEMY_POST_URL} /> }}
          />
        </p>
        <p style={{ paddingTop: '5px' }}>
          <FormattedMessage
            id='dismissable_banner.activity_log_clear'
            defaultMessage='Note: Activities will only be logged while Mastodon is open. When you navigate elsewhere or reload the page, the log will be cleared.'
          />
        </p>
      </DismissableBanner>

      <ActivityLogStream />

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ActivityLog;
