FROM dart:stable AS build
WORKDIR /app

COPY backend/pubspec.* ./backend/
RUN cd backend && dart pub get

COPY . .
RUN cd backend && dart pub get --offline

FROM dart:stable
WORKDIR /app/backend

COPY --from=build /app /app

ENV HOST=0.0.0.0
ENV PORT=8080
EXPOSE 8080

CMD ["dart", "run", "bin/server.dart"]
