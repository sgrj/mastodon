import { useCallback, useRef } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { Helmet } from '@unhead/react/helmet';
import { ActivityWorkshop as Workshop } from 'activitypub-visualization';

import ManufacturingIcon from '@/material-icons/400-24px/manufacturing.svg?react';
import {
  setWorkshopActivity,
  setWorkshopInboxUrl,
} from 'mastodon/actions/activity_workshop';
import { apiRequestPost } from 'mastodon/api';
import { BlogLink, NEW_FEATURES_POST_URL } from 'mastodon/components/blog_link';
import { Column } from 'mastodon/components/column';
import type { ColumnRef } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import { DismissableBanner } from 'mastodon/components/dismissable_banner';
import { useTheme } from 'mastodon/hooks/useTheme';
import { useAppDispatch, useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  heading: {
    id: 'column.activity_workshop',
    defaultMessage: 'Activity Workshop',
  },
});

const WorkshopContent: React.FC = () => {
  const dispatch = useAppDispatch();
  const darkMode = useTheme() === 'dark';

  const activity = useAppSelector((state) => state.activity_workshop.activity);
  const inboxUrl = useAppSelector((state) => state.activity_workshop.inboxUrl);

  const handleActivityChange = useCallback(
    (value: string) => {
      dispatch(setWorkshopActivity(value));
    },
    [dispatch],
  );

  const handleInboxUrlChange = useCallback(
    (value: string) => {
      dispatch(setWorkshopInboxUrl(value));
    },
    [dispatch],
  );

  // The library checks that the inbox is an https URL and that the activity parses
  // before it ever calls this, and it reports a rejection to the student as "Failed
  // to send" -- so this has to reject when the server refuses. `apiRequestPost` is
  // axios and does exactly that; the fork returned the bare `fetch` promise, which
  // resolves on a 500 and reported every failure as a success.
  //
  // Nothing is validated here on purpose. `POST /api/v1/activity` signs and
  // delivers whatever object this sends; seeing a receiving server choke on a
  // hand-written activity is the exercise.
  const handleSubmit = useCallback(async () => {
    await apiRequestPost('v1/activity', {
      inbox_url: inboxUrl,
      activity: JSON.parse(activity) as unknown,
    });
  }, [activity, inboxUrl]);

  return (
    <div className={darkMode ? 'dark' : undefined} style={{ height: '100%' }}>
      <Workshop
        activity={activity}
        inboxUrl={inboxUrl}
        onActivityChange={handleActivityChange}
        onInboxUrlChange={handleInboxUrlChange}
        onSubmit={handleSubmit}
      />
    </div>
  );
};

const ActivityWorkshop: React.FC<{ multiColumn?: boolean }> = ({
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
        icon='wrench'
        iconComponent={ManufacturingIcon}
        title={intl.formatMessage(messages.heading)}
        onClick={handleHeaderClick}
        multiColumn={multiColumn}
      />

      <DismissableBanner id='activity_workshop'>
        <p>
          <FormattedMessage
            id='dismissable_banner.activity_workshop_information'
            defaultMessage='The Activity Workshop allows you to hand-craft your own activities and send them to inboxes of other actors. You can find more information on my {blog}.'
            values={{ blog: <BlogLink href={NEW_FEATURES_POST_URL} /> }}
          />
        </p>
      </DismissableBanner>

      <WorkshopContent />

      <Helmet>
        <title>{intl.formatMessage(messages.heading)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default ActivityWorkshop;
