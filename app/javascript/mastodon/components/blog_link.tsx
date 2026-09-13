// Every academy column ends its explanatory banner with a link to the post that
// introduced the feature. The fork wrote the anchor out by hand in each of them;
// there are four now, and `a.blog-link` in `styles/mastodon/components.scss` is
// the rule that colours it.

export const ACADEMY_POST_URL =
  'https://seb.jambor.dev/posts/activitypub-academy/';
export const NEW_FEATURES_POST_URL =
  'https://seb.jambor.dev/posts/new-features-for-activitypub-academy/';

export const BlogLink: React.FC<{ href: string }> = ({ href }) => (
  <a className='blog-link' href={href}>
    blog
  </a>
);
