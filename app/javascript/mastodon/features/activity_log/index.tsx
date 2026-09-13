import { useCallback, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { ActivityPubVisualization } from 'activitypub-visualization';

import CommentIcon from '@/material-icons/400-24px/comment.svg?react';
import { Column } from 'mastodon/components/column';
import type { ColumnRef } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { DismissableBanner } from 'mastodon/components/dismissable_banner';
import { useHotkeys } from 'mastodon/components/hotkeys';
import { useTheme } from 'mastodon/hooks/useTheme';
import { useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  heading: { id: 'column.activity_log', defaultMessage: 'Activity Log' },
});

const BlogLink: React.FC = () => (
  <a
    className='blog-link'
    href='https://seb.jambor.dev/posts/activitypub-academy/'
  >
    blog
  </a>
);

const ActivityLogStream: React.FC = () => {
  const logs = useAppSelector((state) => state.activity_log.logs);
  const darkMode = useTheme() === 'dark';

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
          values={{ blog: <BlogLink /> }}
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
      {/* The Explorer and Workshop link-outs (clickableLinks / onLinkClick,
          showExplorerLink, showWorkshopLink) are deliberately not wired yet:
          neither feature has an SPA route, so every one of those links would
          land on BundleColumnError. They arrive with those features. */}
      <ActivityPubVisualization logs={logs} />
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
            values={{ blog: <BlogLink /> }}
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
