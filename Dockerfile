FROM ruby:3.4.5

WORKDIR /app

COPY . .

RUN bundle install -j $(nproc)

CMD [ "ruby", "app.rb" ]
