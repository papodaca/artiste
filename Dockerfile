FROM ruby:3.4.5

WORKDIR /app

COPY . .

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y libimage-exiftool-perl curl imagemagick \
  && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs \
  && corepack enable yarn \
  && bundle install -j $(nproc) \
  && cd frontend && yarn install && yarn build && cd - \
  && rm -rf frontend/node_modules \
  && DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs \
  && rm -rf /var/lib/apt/lists/*

CMD [ "ruby", "app.rb" ]
EXPOSE 4567
