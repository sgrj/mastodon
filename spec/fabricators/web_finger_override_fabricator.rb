# frozen_string_literal: true

Fabricator(:web_finger_override) do
  account
  value do |attrs|
    Oj.dump(
      {
        subject: "acct:#{attrs[:account].username}@#{Rails.configuration.x.web_domain}",
        aliases: ["https://#{Rails.configuration.x.web_domain}/@#{attrs[:account].username}"],
        links: [
          {
            rel: 'self',
            type: 'application/activity+json',
            href: "https://#{Rails.configuration.x.web_domain}/users/#{attrs[:account].username}",
          },
        ],
      },
      mode: :compat
    )
  end
end
