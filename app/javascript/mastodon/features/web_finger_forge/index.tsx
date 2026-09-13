import { useCallback, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { WebFingerForge as Forge } from 'activitypub-visualization';

import ContactMailIcon from '@/material-icons/400-24px/contact_mail.svg?react';
import { apiRequestGet, apiRequestPost } from 'mastodon/api';
import { BlogLink, NEW_FEATURES_POST_URL } from 'mastodon/components/blog_link';
import { Column } from 'mastodon/components/column';
import type { ColumnRef } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { DismissableBanner } from 'mastodon/components/dismissable_banner';
import { useTheme } from 'mastodon/hooks/useTheme';

const messages = defineMessages({
  heading: { id: 'column.web_finger_forge', defaultMessage: 'WebFinger Forge' },
});

// The editor is seeded with whatever `/.well-known/webfinger` currently serves for
// this account -- the stored override if there is one, otherwise the document
// Mastodon would generate -- so a student starts from something real and edits it.
// Both calls go through axios, which rejects on a non-2xx; the library turns that
// into "Failed to load" / "Failed to send" in the column.
const loadWebFinger = async () => {
  const body = await apiRequestGet('v1/webfinger');

  return JSON.stringify(body, null, 2);
};

const submitWebFinger = async (value: string) => {
  await apiRequestPost('v1/webfinger', { value });
};

const ForgeContent: React.FC = () => {
  const darkMode = useTheme() === 'dark';

  return (
    <div className={darkMode ? 'dark' : undefined} style={{ height: '100%' }}>
      <Forge loadData={loadWebFinger} onSubmit={submitWebFinger} />
    </div>
  );
};

const WebFingerForge: React.FC<{ multiColumn?: boolean }> = ({
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
        icon='hand-pointer-o'
        iconComponent={ContactMailIcon}
        title={intl.formatMessage(messages.heading)}
        onClick={handleHeaderClick}
        multiColumn={multiColumn}
      />

      <DismissableBanner id='web_finger_forge'>
        <p>
          <FormattedMessage
            id='dismissable_banner.web_finger_forge_information'
            defaultMessage='The WebFinger Forge allows you to control the data that is returned when the WebFinger endpoint for your actor is called. You can find more information on my {blog}.'
            values={{ blog: <BlogLink href={NEW_FEATURES_POST_URL} /> }}
          />
        </p>
      </DismissableBanner>

      <ForgeContent />

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default WebFingerForge;
