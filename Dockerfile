FROM ruby:3.4.5

WORKDIR /app

COPY . .

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y libimage-exiftool-perl imagemagick \
  && rm -rf /var/lib/apt/lists/* \
  && bundle install -j $(nproc)

CMD [ "ruby", "app.rb" ]
EXPOSE 4567
EXPOSE 4568
