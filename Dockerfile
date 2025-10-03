# syntax=docker/dockerfile:1

FROM ruby:3.2-slim AS build

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development test" \
    RAILS_ENV=production \
    RACK_ENV=production

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev git curl ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle lock --add-platform x86_64-linux && \
    bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs=4 --retry=3

COPY . .

RUN SECRET_KEY_BASE=dummy bundle exec rake assets:precompile

FROM ruby:3.2-slim AS app

ENV RAILS_ENV=production \
    RACK_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    PORT=80

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends libpq5 libyaml-0-2 curl wget ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p log storage tmp tmp/pids tmp/sockets db && \
    chown -R rails:rails log storage tmp db

COPY bin/docker-entrypoint /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

USER 1000:1000

EXPOSE 80

ENTRYPOINT ["docker-entrypoint"]
CMD ["./bin/thrust", "./bin/rails", "server"]