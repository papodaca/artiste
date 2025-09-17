FROM node:24-alpine AS frontend-builder

WORKDIR /app/frontend

COPY frontend/package.json frontend/yarn.lock ./
RUN corepack enable && yarn install --frozen-lockfile
COPY frontend/ .
RUN yarn build

FROM ruby:3.4.5

WORKDIR /app

COPY . .

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y libimage-exiftool-perl imagemagick \
  && rm -rf /var/lib/apt/lists/* \
  && bundle install -j $(nproc)

COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

CMD [ "ruby", "app.rb" ]
EXPOSE 4567
EXPOSE 4568
