FROM ruby:3.4

WORKDIR /app

COPY . .

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y libimage-exiftool-perl \
  && bundle install -j $(nproc) \
  && rm -rf /var/lib/apt/lists/*

CMD [ "ruby", "app.rb" ]
