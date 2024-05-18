FROM ruby:3.3.1

WORKDIR /app

COPY . .

RUN bundle install -j $(nproc)

CMD [ "ruby", "app.rb" ]
